import Foundation

extension BilibiliPlayer {
    enum UserScript {
        static func playbackBridge(showsNativeControls: Bool) -> String {
            let hideNativeControls = showsNativeControls ? "false" : "true"
            return """
            (function () {
                if (window.__bilibiliPlayerKitPlaybackBridgeInstalled) {
                    return;
                }
                window.__bilibiliPlayerKitPlaybackBridgeInstalled = true;

                const hideNativeControls = \(hideNativeControls);
                const messageHandlerName = 'bilibiliPlayerKit';

                function findVideo() {
                    return document.querySelector('video');
                }

                function installControlStyles() {
                    if (!hideNativeControls || document.getElementById('bilibili-player-kit-control-style')) {
                        return;
                    }
                    const style = document.createElement('style');
                    style.id = 'bilibili-player-kit-control-style';
                    style.textContent = [
                        '.bpx-player-control-wrap',
                        '.bpx-player-top-wrap',
                        '.bpx-player-sending-area',
                        '.bilibili-player-video-control',
                        '.bilibili-player-video-sendbar',
                        '.bilibili-player-video-top',
                        '.bilibili-player-video-danmaku',
                        '.bpx-player-dm-root',
                        '.bpx-player-toast-wrap',
                        '.bpx-player-toast',
                        '.bpx-player-toast-text'
                    ].join(',') + '{display:none!important;opacity:0!important;pointer-events:none!important;}';
                    document.documentElement.appendChild(style);
                }

                function elementContainsMedia(element) {
                    return !!(element && element.querySelector && element.querySelector('video, iframe'));
                }

                function looksLikeMainContainer(element) {
                    if (!element || !element.getBoundingClientRect) {
                        return false;
                    }
                    const rect = element.getBoundingClientRect();
                    const viewportWidth = window.innerWidth || document.documentElement.clientWidth || 0;
                    const viewportHeight = window.innerHeight || document.documentElement.clientHeight || 0;
                    return rect.width > viewportWidth * 0.65 || rect.height > viewportHeight * 0.65;
                }

                function movePromotionalOverlayToCorner(element) {
                    if (!element || elementContainsMedia(element)) {
                        return;
                    }
                    element.style.setProperty('position', 'fixed', 'important');
                    element.style.setProperty('top', '8px', 'important');
                    element.style.setProperty('right', '8px', 'important');
                    element.style.setProperty('left', 'auto', 'important');
                    element.style.setProperty('bottom', 'auto', 'important');
                    element.style.setProperty('transform', 'scale(0.72)', 'important');
                    element.style.setProperty('transform-origin', 'top right', 'important');
                    element.style.setProperty('z-index', '2147483647', 'important');
                    element.style.setProperty('opacity', '0.65', 'important');
                    element.style.setProperty('pointer-events', 'none', 'important');
                }

                function hidePromotionalOverlay(element) {
                    if (!element || elementContainsMedia(element)) {
                        return false;
                    }
                    if (looksLikeMainContainer(element)) {
                        movePromotionalOverlayToCorner(element);
                        return false;
                    }
                    element.style.setProperty('display', 'none', 'important');
                    element.style.setProperty('opacity', '0', 'important');
                    element.style.setProperty('pointer-events', 'none', 'important');
                    return true;
                }

                function promotionalOverlayTarget(node) {
                    const preferred = node.closest('a, button, [role="button"], .bpx-player-toast, .bpx-player-toast-text, .bpx-player-cmd-dm-wrap') || node;
                    if (!elementContainsMedia(preferred) && !looksLikeMainContainer(preferred)) {
                        return preferred;
                    }
                    if (!elementContainsMedia(node) && !looksLikeMainContainer(node)) {
                        return node;
                    }
                    return null;
                }

                function suppressPromotionalOverlays() {
                    if (!hideNativeControls) {
                        return;
                    }
                    const blockedTexts = [
                        '前往哔哩哔哩',
                        '观看更高清',
                        '进入哔哩哔哩'
                    ];
                    document.querySelectorAll('a, button, div, span').forEach(function (node) {
                        const text = (node.innerText || node.textContent || '').replace(/\\s+/g, '');
                        if (!text || !blockedTexts.some(function (blockedText) { return text.indexOf(blockedText) !== -1; })) {
                            return;
                        }
                        const target = promotionalOverlayTarget(node);
                        if (target) {
                            hidePromotionalOverlay(target);
                        }
                    });
                }

                function prepareVideo(video) {
                    if (!video) {
                        return;
                    }
                    video.setAttribute('playsinline', '');
                    video.setAttribute('webkit-playsinline', '');
                    video.setAttribute('x5-playsinline', '');
                    video.setAttribute('x5-video-player-type', 'h5');
                    video.disablePictureInPicture = true;
                    if (hideNativeControls) {
                        video.controls = false;
                        video.removeAttribute('controls');
                    }
                }

                function postStatus() {
                    const video = findVideo();
                    if (!video) {
                        return;
                    }
                    prepareVideo(video);
                    try {
                        window.webkit.messageHandlers[messageHandlerName].postMessage({
                            kind: 'status',
                            currentTime: Number.isFinite(video.currentTime) ? video.currentTime : 0,
                            duration: Number.isFinite(video.duration) ? video.duration : 0,
                            paused: !!video.paused,
                            ended: !!video.ended,
                            readyState: video.readyState || 0
                        });
                    } catch (_) {}
                }

                function applyCommand(command) {
                    const video = findVideo();
                    if (!video || !command || command.type !== 'bilibili-player-kit-command') {
                        return false;
                    }
                    prepareVideo(video);
                    switch (command.command) {
                    case 'play':
                        video.play();
                        break;
                    case 'pause':
                        video.pause();
                        break;
                    case 'seek':
                        if (Number.isFinite(command.value) && command.value >= 0) {
                            video.currentTime = command.value;
                        }
                        break;
                    case 'stop':
                        video.pause();
                        video.currentTime = 0;
                        break;
                    case 'setMuted':
                        video.muted = !!command.value;
                        break;
                    case 'setRate':
                        if (Number.isFinite(command.value) && command.value > 0) {
                            video.playbackRate = command.value;
                        }
                        break;
                    default:
                        return false;
                    }
                    postStatus();
                    return true;
                }

                window.__bilibiliPlayerKitControl = applyCommand;
                window.addEventListener('message', function (event) {
                    applyCommand(event.data);
                });

                ['loadedmetadata', 'play', 'playing', 'pause', 'ended', 'timeupdate', 'ratechange', 'volumechange'].forEach(function (eventName) {
                    document.addEventListener(eventName, function (event) {
                        if (event.target && event.target.tagName === 'VIDEO') {
                            prepareVideo(event.target);
                            postStatus();
                        }
                    }, true);
                });

                function leaveFullscreenIfNeeded() {
                    if (!hideNativeControls) {
                        return;
                    }
                    try {
                        if (document.fullscreenElement && document.exitFullscreen) {
                            document.exitFullscreen();
                        }
                    } catch (_) {}
                    try {
                        if (document.webkitFullscreenElement && document.webkitExitFullscreen) {
                            document.webkitExitFullscreen();
                        }
                    } catch (_) {}
                }

                document.addEventListener('fullscreenchange', leaveFullscreenIfNeeded, true);
                document.addEventListener('webkitfullscreenchange', leaveFullscreenIfNeeded, true);

                new MutationObserver(function () {
                    installControlStyles();
                    suppressPromotionalOverlays();
                    prepareVideo(findVideo());
                    postStatus();
                }).observe(document.documentElement, {
                    subtree: true,
                    childList: true,
                    attributes: true,
                    attributeFilter: ['controls']
                });

                installControlStyles();
                suppressPromotionalOverlays();
                prepareVideo(findVideo());
                setInterval(suppressPromotionalOverlays, 500);
                setInterval(postStatus, 500);
            })();
            """
        }

        static let preferAVCPlayback = """
        (function () {
            window.__bilibiliPlayerKitPreferAVC = true;

            function patchConfig(value) {
                if (value && typeof value === 'object') {
                    value.enableHEVC = false;
                    value.enableAV1 = false;
                    value.codec = 'avc';
                    value.preferCodec = 'avc';
                }
                return value;
            }

            try {
                if (window.nano && typeof window.nano.createPlayer === 'function' && !window.nano.__bpkPatched) {
                    const originalCreatePlayer = window.nano.createPlayer;
                    window.nano.createPlayer = function (config) {
                        return originalCreatePlayer.call(this, patchConfig(config));
                    };
                    window.nano.__bpkPatched = true;
                }
            } catch (_) {}

            try {
                const originalAppendChild = Element.prototype.appendChild;
                Element.prototype.appendChild = function (node) {
                    if (node && node.tagName === 'SCRIPT' && typeof node.text === 'string') {
                        node.text = node.text
                            .replace(/enableHEVC\\s*:\\s*true/g, 'enableHEVC: false')
                            .replace(/enableAV1\\s*:\\s*true/g, 'enableAV1: false');
                    }
                    return originalAppendChild.call(this, node);
                };
            } catch (_) {}
        })();
        """
    }
}
