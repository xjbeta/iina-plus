$ = function(a) {
    return document.getElementById(a);
};
var isLiving = true;
var defWidth = 680;
var uuid = '';

var flvPlayer;
var videoDuration;


function print(text) {
    window.webkit.messageHandlers.print.postMessage(text);
};

var flvjsLog = function(type, str) {
    print(str);
};

function flv_destroy() {
    flvPlayer.pause();
    flvPlayer.unload();
    flvPlayer.detachMediaElement();
    flvPlayer.destroy();
    flvPlayer = null;
    flvjs.LoggingControl.removeLogListener(flvjsLog);

    document.getElementById('videoElement').replaceWith(document.getElementById('videoElement').cloneNode());
};

window.openUrl = function(url) {
    if (flvPlayer != null) {
        flv_destroy();
    };

    if (flvjs.isSupported()) {
        var videoElement = document.getElementById('videoElement');

        var mediaDataSource = {
            type: 'flv',
            hasAudio: true,
            hasVideo: true,
            isLive: true,
            withCredentials: false,
            url: url
        };

        flvPlayer = flvjs.createPlayer(mediaDataSource, {
            enableWorker: false,
            lazyLoadMaxDuration: 3 * 60,
            seekType: 'range',
        });

        flvjs.LoggingControl.addLogListener(flvjsLog);

        videoElement.addEventListener("loadeddata", function(e) {
            print("loadeddata");
            window.webkit.messageHandlers.size.postMessage([videoElement.videoWidth, videoElement.videoHeight]);
        });
        videoElement.addEventListener("loadedmetadata", function(e) {
            print("loadedmetadata");
        });
        videoElement.addEventListener("ended", function(e) {
            window.webkit.messageHandlers.end.postMessage();
        });
        videoElement.addEventListener("error", function(e) {
            print("error");
        });
        videoElement.addEventListener("resize", function(e) {
            window.webkit.messageHandlers.size.postMessage([videoElement.videoWidth, videoElement.videoHeight]);
        });

        videoElement.addEventListener("durationchange", function(e) {
            var d = parseInt(videoElement.duration, 10);
            if (videoDuration != d) {
                videoDuration = d;
                window.webkit.messageHandlers.duration.postMessage(d);
            };
        });

        flvPlayer.attachMediaElement(videoElement);

        flvPlayer.load();
        flvPlayer.play();

    }
};

window.dmMessage = function(event) {    
    if (event.method != 'sendDM') {
        console.log(event.method, event.text);
    };
    
    switch(event.method) {
    case 'start':
        window.cm.start();
        break;
    case 'stop':
        window.cm.stop();
        window.cm.clear();
        break;
    case 'initDM':
        window.initDM();
        break;
    case 'resize':
        window.resize();
        break;
    case 'customFont':
        window.customFont(event.text);
        break;
    case 'loadDM':
        if (event.text == 'acfun') {
            loadDM('/danmaku/iina-plus-danmaku.json', 'acfun');
        } else {
            loadDM('/danmaku/' + 'danmaku' + '-' + uuid + '.xml');
            
            console.log('/danmaku/' + 'danmaku' + '-' + uuid + '.xml');
        }
        isLiving = false;
        break;
    case 'sendDM':
        if (document.visibilityState == 'visible') {
            var comment = {
                'text': event.text,
                'stime': 0,
                'mode': 1,
                'color': 0xffffff,
                'border': false
            };
            window.cm.send(comment);
        }
        break
    case 'liveDMServer':
        updateStatus(event.text);
        break
    case 'dmSpeed':
        defWidth = event.text;
        window.resize();
        break
    case 'dmOpacity':
        window.cm.options.global.opacity = event.text;
        break
    case 'dmFontSize':
        // updateStatus(event.text);
        break
    case 'dmBlockList':
        let t = event.text;
        if (t.includes('List')) {
            window.loadFilter('/danmaku/iina-plus-blockList.xml');
        }
        if (t.includes('Top')) {
            cm.filter.allowTypes[5] = false;
        }
        if (t.includes('Bottom')) {
            cm.filter.allowTypes[4] = false;
        }
        if (t.includes('Scroll')) {
            cm.filter.allowTypes[1] = false;
            cm.filter.allowTypes[2] = false;
        }
        if (t.includes('Color')) {
            cm.filter.addRule({
                subject: 'color',
                op: '=',
                value: 16777215,
                mode: 'accept'
            });
        }
        if (t.includes('Advanced')) {
            cm.filter.allowTypes[7] = false;
            cm.filter.allowTypes[8] = false;
        }
        break
    default:
        break;
    };
};

function bind() {
    window.cm = new CommentManager($('commentCanvas'));
    cm.init();
    window.resize = function () {
        var scale = $("player").offsetWidth / defWidth;
        window.cm.options.scroll.scale = scale;
        cm.setBounds();
    };

    document.addEventListener('visibilitychange', function () {
        if (document.visibilityState == 'visible') {
            console.log('visible');
            cm.start();
            cm.clear();
        } else {
            console.log('hidden');
            cm.stop();
            cm.clear();
        };
        resize();
    });

    window.initDM = function() {
        if (window._provider && window._provider instanceof CommentProvider) {
            window._provider.destroy();
        }
        window._provider = new CommentProvider();
        cm.clear();
        window._provider.addTarget(cm);
        resize();
        cm.init();
        cm.start();
    };

    window.customFont = function(fontStyle) {
        var element = document.getElementsByTagName("style"), index;
        for (index = element.length - 1; index >= 0; index--) {
        element[index].parentNode.removeChild(element[index]);
        }

        var style = document.createElement('style');
        style.type = 'text/css';
        style.innerHTML = fontStyle;
        document.getElementsByTagName('head')[0].appendChild(style);
        window.cm.options.global.className = 'customFont'
    };
    
    /** Load **/
    window.loadDM = function(dmf, provider) {
        if (window._provider && window._provider instanceof CommentProvider) {
            window._provider.destroy();
        }
        window._provider = new CommentProvider();
        cm.clear();
        window._provider.addTarget(cm);
        resize();
        switch (provider) {
            case "acfun":
                window._provider.addStaticSource(
                    CommentProvider.JSONProvider('GET', dmf),
                    CommentProvider.SOURCE_JSON).addParser(
                    new AcfunFormat.JSONParser(),
                    CommentProvider.SOURCE_JSON);
                break;
            case "cdf":
                window._provider.addStaticSource(
                    CommentProvider.JSONProvider('GET', dmf),
                    CommentProvider.SOURCE_JSON).addParser(
                    new CommonDanmakuFormat.JSONParser(),
                    CommentProvider.SOURCE_JSON);
                break;
            case "bilibili-text":
                window._provider.addStaticSource(
                    CommentProvider.TextProvider('GET', dmf),
                    CommentProvider.SOURCE_TEXT).addParser(
                    new BilibiliFormat.TextParser(),
                    CommentProvider.SOURCE_TEXT);
                break;
            case "bilibili":
            default:
                window._provider.addStaticSource(
                    CommentProvider.XMLProvider('GET', dmf),
                    CommentProvider.SOURCE_XML).addParser(
                    new BilibiliFormat.XMLParser(),
                    CommentProvider.SOURCE_XML);
                break;
        }
        window._provider.start().then(function() {
            cm.start();
        }).catch(function(e) {
            alert(e);
        });
    };

    window.loadFilter = function(ff) {
        cm.filter.rules = [];
        CommentProvider.XMLProvider("GET", ff)
        .then(result => result.getElementsByTagName("item"))
        .then(items => [...items].map(r => r.textContent).filter(r => r.startsWith('r=')).map(r => r.replace('r=', '')))
        .then(function(values) {
            values.forEach(v =>
                cm.filter.addRule({
                    "subject": "text",
                    "op": "~",
                    "value": v,
                    "mode": "reject"
                })
            )
        });
    };
};

function updateStatus(status){
    switch(status) {
    case 'warning':
        document.getElementById("status").style.backgroundColor="#FFB742"
        break
    case 'error':
        document.getElementById("status").style.backgroundColor="#FF2640"
        break
    default:
        document.getElementById("status").style.backgroundColor=""
        break
    }
}

function initContent(){
    bind();
    initDM();
    resize();
    // Block unknown types.
    // https://github.com/jabbany/CommentCoreLibrary/issues/97
    cm.filter.allowUnknownTypes = false;
    console.log('initContent', id);
}
