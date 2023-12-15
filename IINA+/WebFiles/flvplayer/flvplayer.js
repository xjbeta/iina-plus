$ = function(a) {
    return document.getElementById(a);
};
var isLiving = true;
var defWidth = 680;
var uuid = '';

var player;
var videoDuration;


function print(text) {
    window.webkit.messageHandlers.print.postMessage(text);
};

var playerLogListener = function(type, str) {
    print(str);
};

function playerDestroy() {
    player.pause();
    player.unload();
    player.detachMediaElement();
    player.destroy();
    player = null;
    mpegts.LoggingControl.removeLogListener(playerLogListener);

    document.getElementById('videoElement').replaceWith(document.getElementById('videoElement').cloneNode());
};

window.openUrl = function(url) {
    if (player != null) {
        playerDestroy();
    };

	if (mpegts.isSupported()) {
        var videoElement = document.getElementById('videoElement');

        var mediaDataSource = {
            type: 'flv',
			enableWorker: true,
            hasAudio: true,
            hasVideo: true,
            isLive: true,
            withCredentials: false,
			lazyLoad: false,
			rangeLoadZeroStart: true,
            url: url
        };

        player = mpegts.createPlayer(mediaDataSource, {
            lazyLoadMaxDuration: 3 * 60,
            seekType: 'range',
            liveBufferLatencyChasing: true,
            liveBufferLatencyMaxLatency: 8,
            liveBufferLatencyMinRemain: 0.5,
        });

        mpegts.LoggingControl.addLogListener(playerLogListener);

        videoElement.addEventListener("loadeddata", function(e) {
            print("loadeddata");
            window.webkit.messageHandlers.size.postMessage([videoElement.videoWidth, videoElement.videoHeight]);
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

        player.attachMediaElement(videoElement);

        player.load();
        player.play();


        player.on(mpegts.Events.Error, function(data) {
            window.webkit.messageHandlers.error.postMessage(data);
        });

        player.on(mpegts.Events.LOADING_COMPLETE, function(data) {
            window.webkit.messageHandlers.loadingComplete.postMessage(data);
        });

        player.on(mpegts.Events.RECOVERED_EARLY_EOF, function(data) {
            window.webkit.messageHandlers.recoveredEarlyEof.postMessage(data);
        });

        player.on(mpegts.Events.MEDIA_INFO, function(data) {
            window.webkit.messageHandlers.mediaInfo.postMessage(data);
        });

        // player.on(mpegts.Events.METADATA_ARRIVED, function(data) {
        //     print(data);
        //     print('METADATA_ARRIVED');
        // });

        
        player.on(mpegts.Events.SCRIPTDATA_ARRIVED, function(data) {
            window.webkit.messageHandlers.metaData.postMessage(data.onMetaData);
        });

        // stuckChecker
        player.on(mpegts.Events.STATISTICS_INFO, function(data) {
            window.webkit.messageHandlers.stuckChecker.postMessage(data.decodedFrames);
        });

        player.on(mpegts.Events.DESTROYING, function(data) {
            print(data);
            print('DESTROYING');
        });

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
        if (document.visibilityState != 'visible') {
            return;
        }
            
        event.dms.forEach(function(element, index) {
            setTimeout(function () {
                var comment = {
                    'text': element.text,
                    'stime': 0,
                    'mode': 1,
                    'color': 0xffffff,
                    'border': false,
                    'imageSrc': element.imageSrc,
                    'imageWidth': element.imageWidth
                };
                window.cm.send(comment);
            }, index * 150);
        });
        break;
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
    console.log('initContent');
}
