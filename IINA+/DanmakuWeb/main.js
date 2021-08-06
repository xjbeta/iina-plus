$ = function(a) {
    return document.getElementById(a);
};
var isLiving = true;
var defWidth = 680;
var uuid = '';

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

function start(websocketServerLocation){
    ws = new WebSocket(websocketServerLocation);
    updateStatus('warning');
    ws.onopen = function(evt) { 
        updateStatus();
        ws.send(uuid);
    };
    ws.onmessage = function(evt) { 
        var event = JSON.parse(evt.data);
        
        if (event.method != 'sendDM') {
            console.log(event.method, event.text);
        }
        
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
        }

    };
    ws.onclose = function(){
        if (isLiving) {
            updateStatus('warning');
            // Try to reconnect in 1 seconds
            setTimeout(function(){start(websocketServerLocation)}, 1000);
        }
    };
}

function initContent(id, port){
    bind();
    initDM();
    resize();
    uuid = id;
    if (port === undefined){
        port = 10980;
    }
    start('ws://127.0.0.1:' + port + '/danmaku-websocket');
    // Block unknown types.
    // https://github.com/jabbany/CommentCoreLibrary/issues/97
    cm.filter.allowUnknownTypes = false;
    console.log('initContent', id);
}
