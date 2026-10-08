import Foundation

extension BilibiliPlayer.UserScript {
    /// Runs in the actual media frame. Control promises resolve on media events,
    /// while the whole loop stays on this side of the WebKit message bridge.
    static let confirmedPlaybackControl = #"""
    let revision = 0;
    let sequence = 0;
    let media = null;
    let loopRange = null;
    let wantsPlayback = false;
    let seeking = false;
    let loopTransition = false;
    let playbackError = null;
    let lastLoopBoundaryTime = null;
    let lastConfirmedTime = 0;
    let boundaryTimer = null;
    let boundaryFrame = null;
    let cancelWait = null;
    const operationTimeout = 10000;
    const seekTolerance = 0.025;

    function clearBoundary() {
        clearTimeout(boundaryTimer);
        cancelAnimationFrame(boundaryFrame);
        boundaryTimer = null;
        boundaryFrame = null;
    }

    function invalidateWait() {
        if (cancelWait) cancelWait();
        cancelWait = null;
        clearBoundary();
    }

    function adoptVideo(video) {
        if (media === video) return;
        invalidateWait();
        media = video;
        seeking = false;
        loopTransition = false;
        wantsPlayback = !video.paused;
        lastConfirmedTime = video.currentTime || 0;
    }

    function tokenFor(video) { return { revision: revision, video: video }; }
    function isCurrent(token) { return token.revision === revision && token.video === media; }
    function requireCurrent(token) {
        if (!isCurrent(token)) throw new Error('Bilibili operation superseded');
    }

    function effectiveLoopEnd(video) {
        return Number.isFinite(video.duration) && video.duration > 0
            ? Math.min(loopRange.end, video.duration) : loopRange.end;
    }

    function boundedPosition(value) {
        if (!loopRange) return value;
        return Math.max(loopRange.start, Math.min(value, loopRange.end));
    }

    function postStatus() {
        const video = findVideo();
        if (!video) return;
        adoptVideo(video);
        prepareVideo(video);
        if (loopRange && wantsPlayback && !seeking && (video.ended ||
            (!video.paused && video.currentTime >= effectiveLoopEnd(video)))) {
            beginLoop(video);
        }
        if (!seeking) lastConfirmedTime = video.currentTime;
        try {
            window.webkit.messageHandlers[messageHandlerName].postMessage({
                kind: 'status', sessionID: bridgeSessionID, revision: revision,
                sequence: ++sequence,
                currentTime: boundedPosition(lastConfirmedTime),
                rawCurrentTime: video.currentTime,
                loopBoundaryTime: lastLoopBoundaryTime,
                duration: Number.isFinite(video.duration) ? video.duration : 0,
                paused: (seeking || loopTransition) && wantsPlayback ? false : !!video.paused,
                ended: loopRange ? false : !!video.ended,
                readyState: video.readyState || 0,
                seeking: seeking || video.seeking,
                loopTransition: loopTransition,
                playbackError: playbackError
            });
        } catch (_) {}
    }

    function waitForSeek(video, target, token) {
        return new Promise(function (resolve, reject) {
            let finished = false;
            let seekCompleted = false;
            let timeout;
            let poll;
            function cleanup() {
                clearTimeout(timeout);
                clearInterval(poll);
                video.removeEventListener('seeked', onSeeked);
                video.removeEventListener('canplay', check);
                video.removeEventListener('loadeddata', check);
                video.removeEventListener('error', onError);
                video.removeEventListener('emptied', onError);
                if (cancelWait === cancel) cancelWait = null;
            }
            function finish(error) {
                if (finished) return;
                finished = true;
                cleanup();
                if (error) reject(error); else resolve();
            }
            function cancel() { finish(new Error('Bilibili operation superseded')); }
            function onError() { finish(new Error('Bilibili media failed during seek')); }
            function check() {
                if (!isCurrent(token)) { cancel(); return; }
                if (seekCompleted && !video.seeking && video.readyState >= 2 &&
                    Math.abs(video.currentTime - target) <= seekTolerance) finish();
            }
            function onSeeked() { seekCompleted = true; check(); }
            cancelWait = cancel;
            video.addEventListener('seeked', onSeeked);
            video.addEventListener('canplay', check);
            video.addEventListener('loadeddata', check);
            video.addEventListener('error', onError);
            video.addEventListener('emptied', onError);
            timeout = setTimeout(function () { finish(new Error('Bilibili seek timed out')); }, operationTimeout);
            poll = setInterval(check, 25);
            const alreadyAtTarget = !video.seeking && Math.abs(video.currentTime - target) <= seekTolerance;
            try {
                if (alreadyAtTarget) seekCompleted = true;
                else video.currentTime = target;
                check();
            } catch (error) { finish(error); }
        });
    }

    function waitForPlay(video, token) {
        return new Promise(function (resolve, reject) {
            let finished = false;
            let timeout;
            function finish(error) {
                if (finished) return;
                finished = true;
                clearTimeout(timeout);
                if (cancelWait === cancel) cancelWait = null;
                if (error) reject(error); else resolve();
            }
            function cancel() { finish(new Error('Bilibili operation superseded')); }
            cancelWait = cancel;
            timeout = setTimeout(function () { finish(new Error('Bilibili play timed out')); }, operationTimeout);
            try {
                Promise.resolve(video.play()).then(function () {
                    if (!isCurrent(token) || !wantsPlayback) { cancel(); return; }
                    if (video.paused) finish(new Error('Bilibili did not start playback'));
                    else finish();
                }, finish);
            } catch (error) { finish(error); }
        });
    }

    async function positionVideo(video, target, token, isLoop) {
        seeking = true;
        loopTransition = isLoop;
        clearBoundary();
        video.pause();
        postStatus();
        await waitForSeek(video, target, token);
        requireCurrent(token);
        lastConfirmedTime = video.currentTime;
        seeking = false;
        if (wantsPlayback) await waitForPlay(video, token);
        requireCurrent(token);
        loopTransition = false;
        postStatus();
        scheduleBoundary();
    }

    function beginLoop(video) {
        if (!loopRange || !wantsPlayback || seeking || loopTransition) return;
        const token = tokenFor(video);
        const start = loopRange.start;
        lastLoopBoundaryTime = video.currentTime;
        // positionVideo marks the transition and pauses synchronously, before
        // an out-of-range progress message can reach the host.
        positionVideo(video, start, token, true).catch(function (error) {
            if (!isCurrent(token)) return;
            wantsPlayback = false;
            seeking = false;
            loopTransition = false;
            playbackError = String(error.message || error);
            video.pause();
            clearBoundary();
            postStatus();
        });
    }

    function checkBoundary() {
        clearBoundary();
        const video = findVideo();
        if (!video) return;
        adoptVideo(video);
        if (!loopRange || !wantsPlayback || seeking || (video.paused && !video.ended)) return;
        if (video.ended || video.currentTime >= effectiveLoopEnd(video)) beginLoop(video);
        else scheduleBoundary();
    }

    function scheduleBoundary() {
        clearBoundary();
        if (!media || !loopRange || !wantsPlayback || seeking || (media.paused && !media.ended)) return;
        const remaining = (effectiveLoopEnd(media) - media.currentTime) / Math.max(media.playbackRate, 0.01);
        boundaryTimer = setTimeout(checkBoundary, Math.max(1, Math.min(remaining * 1000, 2000)));
        boundaryFrame = requestAnimationFrame(checkBoundary);
    }

    async function applyCommand(command) {
        const video = findVideo();
        if (!video) throw new Error('Bilibili media element is unavailable');
        if (!command || command.sessionID !== bridgeSessionID) throw new Error('Bilibili source changed');
        adoptVideo(video);
        prepareVideo(video);
        const transport = ['play', 'pause', 'seek', 'setLoopRange', 'stop'].includes(command.command);
        if (command.revision < revision) throw new Error('Bilibili operation superseded');
        if (transport) {
            revision = command.revision;
            invalidateWait();
            seeking = false;
            loopTransition = false;
            playbackError = null;
        }
        const token = tokenFor(video);
        try {
            switch (command.command) {
            case 'play':
                wantsPlayback = true;
                if (video.seeking || (loopRange && (video.currentTime < loopRange.start || video.currentTime >= loopRange.end))) {
                    const start = loopRange && (video.currentTime < loopRange.start || video.currentTime >= loopRange.end)
                        ? loopRange.start : video.currentTime;
                    await positionVideo(video, start, token, false);
                } else {
                    await waitForPlay(video, token);
                }
                break;
            case 'pause':
                wantsPlayback = false;
                video.pause();
                break;
            case 'seek':
                if (!Number.isFinite(command.value) || command.value < 0) throw new Error('Invalid Bilibili seek target');
                const target = loopRange && (command.value < loopRange.start || command.value >= loopRange.end)
                    ? loopRange.start : command.value;
                await positionVideo(video, target, token, false);
                break;
            case 'setLoopRange':
                if (command.value !== null && (!Number.isFinite(command.value.start) ||
                    !Number.isFinite(command.value.end) || command.value.start < 0 || command.value.end <= command.value.start)) {
                    throw new Error('Invalid Bilibili loop range');
                }
                loopRange = command.value;
                if (wantsPlayback) {
                    if (video.seeking || (loopRange && (video.currentTime < loopRange.start || video.currentTime >= loopRange.end))) {
                        const start = loopRange && (video.currentTime < loopRange.start || video.currentTime >= loopRange.end)
                            ? loopRange.start : video.currentTime;
                        await positionVideo(video, start, token, true);
                    } else {
                        await waitForPlay(video, token);
                    }
                }
                break;
            case 'stop':
                wantsPlayback = false;
                loopRange = null;
                video.pause();
                video.currentTime = 0;
                break;
            case 'setMuted':
                video.muted = !!command.value;
                break;
            case 'setRate':
                if (!Number.isFinite(command.value) || command.value <= 0) throw new Error('Invalid Bilibili playback rate');
                video.playbackRate = command.value;
                break;
            default:
                throw new Error('Unknown Bilibili control command');
            }
            requireCurrent(token);
            postStatus();
            scheduleBoundary();
            return { revision: revision, currentTime: video.currentTime };
        } catch (error) {
            if (transport && isCurrent(token)) {
                wantsPlayback = false;
                seeking = false;
                loopTransition = false;
                playbackError = String(error.message || error);
                video.pause();
                clearBoundary();
                postStatus();
            }
            throw error;
        }
    }

    window.__bilibiliPlayerKitControl = applyCommand;
    ['loadedmetadata', 'loadeddata', 'canplay', 'play', 'playing', 'pause', 'ended',
     'seeking', 'seeked', 'waiting', 'error', 'emptied', 'timeupdate', 'ratechange', 'volumechange'].forEach(function (eventName) {
        document.addEventListener(eventName, function (event) {
            if (!event.target || event.target.tagName !== 'VIDEO') return;
            adoptVideo(event.target);
            if (!seeking && !loopTransition) {
                if (eventName === 'play' && !media.paused) wantsPlayback = true;
                if (eventName === 'pause' && media.paused && !(loopRange && media.ended)) wantsPlayback = false;
            }
            postStatus();
            scheduleBoundary();
        }, true);
    });
    """#
}
