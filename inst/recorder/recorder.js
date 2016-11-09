window.shinyRecorder = (function() {
    var shinyrecorder = {
        token: null        // Gets set by parent frame
    };

    // Store previous values for each input. Use JSON so that we can compare
    // non-primitive objects like arrays.
    var previousInputValues = {};

    $(document).on("shiny:inputchanged", function(event) {
        // Check if value has changed from last time.
        var valueJSON = JSON.stringify(event.value);
        if (valueJSON === previousInputValues[event.name])
            return;
        previousInputValues[event.name] = valueJSON;

        sendInputEventToParent(event.inputType, event.name, event.value);
    });


    // Ctrl-click to record an output value
    $(document).on("click", ".shiny-bound-output", function(e) {
        if (!e.ctrlKey)
            return;

        var id = e.target.id;
        var value = Shiny.shinyapp.$values[id];

        sendOutputValueToParent(id, value);
    });


    function sendInputEventToParent(inputType, name, value) {
        parent.postMessage({
            token: shinyrecorder.token,
            inputEvent: { inputType: inputType, name: name, value: value }
        }, "*");
    }

    function sendOutputValueToParent(name, value) {
        parent.postMessage({
            token: shinyrecorder.token,
            outputValue: { name: name, value: value }
        }, "*");
    }


    // ------------------------------------------------------------------------
    // Initialization
    // ------------------------------------------------------------------------
    function initialize() {
        // Save initial values so we can check for changes.
        for (var name in Shiny.shinyapp.$inputValues) {
            previousInputValues[name] = JSON.stringify(Shiny.shinyapp.$inputValues[name]);
        }
    }
    $(document).on("shiny:connected", initialize);


    return shinyrecorder;
})();
