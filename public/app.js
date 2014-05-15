/**
 * Main Fipes JS namespace
 */
window.App = {
    // Namespaces
    Models    : {},
    Views     : {},

    // Instances
    Files     : undefined,
    FipeView  : undefined,
    FilesView : undefined
};

App.Router = Backbone.Router.extend({
    routes: {
        "/"      : "fipes",
        "/:fipe" : "fipe"
    },

    fipes: function() {
        App.Files     = new App.Models.Files;

        App.FipeView  = new App.Views.Fipe({el: $('#main')});
        App.FilesView = new App.Views.Files({
            el         : $('#main .files ul'),
            collection : App.Files
        });
    },

    fipe: function(fid) {
        if (App.Files === undefined) {
            this.fipes();
        }

        var fipe = new App.Models.Fipe({id: fid});
        fipe.open(function(uid) {
            App.Files.fipe = App.Fipe = fipe;
            App.UID        = uid;

            // There is no files yet, sync with the server.
            if (App.Files.length === 0) {
                App.Files.fetch();
            // There is files already, so we save them as we created the
            // fipe.
            } else {
                App.Files.save();
            }
        });
    }

});

/**
 * Helpers. Highly dangerous stuff.
 */
App.Helpers = {

    // Return a human readable format for size (in bytes).
    // Found here:
    //
    //   http://programanddesign.com/js/human-readable-file-size-in-javascript/
    //
    humanSize: function(size, cap) {
        var units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB', 'EB', 'ZB', 'YB'];
        var i = 0;
        while(size >= 1024) {
            if (units.indexOf(cap) === i)
                break;

            size /= 1024;
            ++i;
        }

        return size.toFixed(1) + ' ' + units[i];
    }

};

/**
 * Misc. behaviours, such as global animations, routing...
 */
$(document).ready(function() {
    Backbone.sync = Backbone.TNetStrings.sync;
    App.Routes = new App.Router;

    if (!Backbone.history.start()) {
        App.Routes.navigate('/', true);
    }

    function dispatch(event) {
        var tdt = document.querySelector('.' + event.type);
        var data = event.data
        if (event.type == 'total-data')
            data = App.Helpers.humanSize(parseInt(event.data), "MB")
        if (event.type == 'average-size')
            data = App.Helpers.humanSize(parseInt(event.data))

        tdt.textContent = data;
    };
    var source = new EventSource("/stats")
    source.addEventListener('total-data', dispatch);
    source.addEventListener('total-files', dispatch);
    source.addEventListener('total-uploads', dispatch);
    source.addEventListener('average-size', dispatch);

    window.onbeforeunload = function (event) {
        if (App.Files == undefined || App.Files.size() == 0) {
            return;
        }

        var message = 'If you quit this page, the files you offer will not be available anymore.';
        var event = event || window.event;

        // For IE and Firefox prior to version 4
        if (event) {
            event.returnValue = message;
        }

        // For Safari
        return message;
    };

});

