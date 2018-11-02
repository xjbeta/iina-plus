$ = function(a) {
    return document.getElementById(a);
};


function bind() {
    window.cm = new CommentManager($('commentCanvas'));
    cm.init();
    window.resize = function () {
        var defWidth = 680;
        var scale = $("player").offsetWidth / defWidth;
        window.cm.options.scroll.scale = scale;
        cm.setBounds();
    }

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

    window.customFont = function(font) {
        var element = document.getElementsByTagName("style"), index;
        for (index = element.length - 1; index >= 0; index--) {
        element[index].parentNode.removeChild(element[index]);
        }

        var style = document.createElement('style');
        style.type = 'text/css';
        style.innerHTML = '.customFont {color: #fff;font-family: ' + font + ', SimHei, SimSun, Heiti, "MS Mincho", "Meiryo", "Microsoft YaHei", monospace;font-size: 25px;letter-spacing: 0;line-height: 100%;margin: 0;padding: 3px 0 0 0;position: absolute;text-decoration: none;text-shadow: -1px 0 black, 0 1px black, 1px 0 black, 0 -1px black;-webkit-text-size-adjust: none;-ms-text-size-adjust: none;text-size-adjust: none;-webkit-transform: matrix3d(1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1);transform: matrix3d(1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1);-webkit-transform-origin: 0% 0%;-ms-transform-origin: 0% 0%;transform-origin: 0% 0%;white-space: pre;word-break: keep-all;}';
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

function start(websocketServerLocation){
    ws = new WebSocket(websocketServerLocation);
    ws.open = function(evt) { 
        console.log('WebSocket open');
        ws.send('WebSocket open');
        updateStatus();
    };
    ws.onmessage = function(evt) { 
        var event = JSON.parse(evt.data);
        switch(event.method) {
        case 'start':
            window.cm.start();
            break;
        case 'stop':
            window.cm.stop();
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
            loadDM('/danmaku/iina-plus-danmaku.xml');
            break;
        case 'sendDM':
            var comment = {
                'text': event.text,
                'stime': 0,
                'mode': 1,
                'color': 0xffffff,
                'border': false
            };
            window.cm.send(comment);
            break
        case 'liveDMServer':
            updateStatus(event.text);
        default:
            break;
        }

    };
    ws.onclose = function(){
        updateStatus('warning');
        // Try to reconnect in 1 seconds
        setTimeout(function(){start(websocketServerLocation)}, 1000);
    };
}

window.addEventListener("load", function() {
    bind();
    initDM();
    start('ws://127.0.0.1:19080/danmaku-websocket');
});