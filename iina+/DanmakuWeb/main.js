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

    BaseProvider = function (url) {
        return new Promise(function (resolve, reject) {
            var xhr = new XMLHttpRequest();
            var uri = url;
            xhr.onload = function () {
                if (this.status == 0) {
                    resolve(this.response);
                } else {
                    reject(new Error(this.status + " " + this.statusText));
                }
            };

            xhr.onerror = function () {
                reject(new Error(this.status + " " + this.statusText));
            };

            xhr.open("GET", uri, false);

            // Limit the response type based on input
            xhr.responseType = "document";

            xhr.send();
        });
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
                    // CommentProvider.XMLProvider('GET', dmf),
                    BaseProvider(dmf),
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

window.addEventListener("load", function() {
    bind();
});

