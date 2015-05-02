'use strict'

Utils = window.Utils or {}
log = Utils.log or { i: -> e: -> d: -> }

window.Messanger = window.Messanger or {}
window.Messanger.initConsole = () ->
    @cmd = null
    @callback = null
    @slaveCallback = false
    @send = (cmd, request, callback, slaveCallback = false) ->
        @cmd = cmd
        @callback = callback
        @slaveCallback = slaveCallback
        log.d('Messanger.send(): Sending request to global: ', [request, slaveCallback, callback])
        safari.self.tab.dispatchMessage('consoleRequest', {cmd: cmd, request: request})
    @handleConsoleEvent = (e) ->
        log.d('messanger: get response from ', e)
        if e.name is 'consoleResponse' and e.message.cmd is @cmd
            e.preventDefault()
            #@history.push(e.message)
            if (@slaveCallback)
                @callback?(e.message.response, @slaveCallback)
            else
                @callback?(e.message.response)
window.Messanger.initConsole()
_messanger = window.Messanger

ConsolePanel = (config) ->

    config = config || {}
    name = config.name or 'KTab.ConsolePanel'
    shellViewId = config.shellViewId or 'shell-view'
    shellPanelId = config.shellPanelId or 'shell-panel'
    inputId = config.inputId or 'shell-cli'

    history = new Josh.History({ key: name })
    shell = Josh.Shell({
        history: history
        shell_view_id: shellViewId
        shell_panel_id: shellPanelId
        input_id: inputId
    })

    shell.promptCounter = 0
    shell.onNewPrompt((callback) ->
        shell.promptCounter++
        callback('[' + shell.promptCounter + ']$')
    )

    # Templates
    shell.templates.bindings = _.template("<div><% _.each(items, function(binding, i) { %><div><%- binding %></div><% }); %></div>")


    shell.setCommand = (cmd, completion) ->
        return if not @cmdHandlers[cmd]
        handler = { exec: @cmdHandlers[cmd] }
        if completion? and completion.length
            handler.completion = (cmd, arg, line, callback) ->
                callback(shell.bestMatch(arg, completion))
        @setCommandHandler(cmd, handler)

    shell.showBinding = (key, fkey, binding) ->
        parsedHotKey = Utils.parseHotKeyCode(key, fkey)
        return parsedHotKey.error if parsedHotKey.error
        parsedBinding = Utils.parseBindingObject(binding)
        return parsedBinding.error if parsedBinding.error
        return parsedHotKey.string + '  ' + parsedBinding.string

    shell.showBindings = (response, callback) ->
        bindings = response.results or []
        output = []
        output.push(shell.showBinding(b.key, b.fkey, b.binding)) for b in bindings
        callback?(shell.templates.bindings({items: output}))


    shell.cmdHandlers =
        debug: (cmd, args, callback) ->
            defaultArgs = ['']

        exit: (cmd, args, callback) ->
            callback('Exit kTab console...')
            setTimeout(() ->
                shell.deactivateAndHide?()
                shell.promptCounter = 0
                history.clear()
                $('#' + inputId).parent().empty()
            , 500)

        # e.g. set ctrl+alt+a https://v2ex.com
        set: (cmd, args, callback) ->
            defaultArgs = ['hotkey', 'url']
            parsedArgs = Utils.parseArguments(args, defaultArgs, true)
            return callback('ERROR<args>: Invalid argument(s) given. - [' + parsedArgs.error + ']') if parsedArgs.error

            hotkey = Utils.parseHotKeyString(parsedArgs.hotkey)
            return callback(hotkey.error) if hotkey.error

            url = Utils.parseUrlString(parsedArgs.url)
            return callback(url.error) if url.error

            request =
                key: hotkey.key
                fkey: hotkey.fkey
                name: parsedArgs.name or ''
                type: if url.protocol is 'ktab' then 'action' else 'url'
                url: url.url
                protocol: url.protocol
                dest: url.dest

            _messanger.send('setBinding', request, callback)

        unset: (cmd, args, callback) ->
            defaultArgs = ['hotkey']
            parsedArgs = Utils.parseArguments(args, defaultArgs, true)
            return callback('ERROR<args>: Invalid argument(s) given. - [' + parsedArgs.error + ']') if parsedArgs.error

            hotkey = Utils.parseHotKeyString(parsedArgs.hotkey)
            return callback(hotkey.error) if hotkey.error

            request =
                key: hotkey.key
                fkey: hotkey.fkey

            _messanger.send('unsetBinding', request, callback)

        ls: (cmd, args, callback) ->
            request =
                callback: true
            _messanger.send('showBindings', request, shell.showBindings, callback)

        config: (cmd, args, callback) ->
            defaultArgs = ['option', 'value']
            parsedArgs = Utils.parseArguments(args, defaultArgs, true)
            return callback('ERROR<args>: Invalid argument(s) given. - [' + parsedArgs.error + ']') if parsedArgs.error

            # Extra work for specific configurations
            selects = []
            switch parsedArgs.option
                when 'logLevel'
                    Utils.log.setLevel(parsedArgs.value)
                    selects = Utils.log.levels

            request =
                option: parsedArgs.option
                value: parsedArgs.value
                selects: selects

            _messanger.send('setOption', request, callback)




    # Assign command handlers
    shell.setCommand('set', ['ctrl', 'alt', 'shift', 'escape', 'space', 'tab', 'delete', 'return'])
    shell.setCommand('unset', ['ctrl', 'alt', 'shift', 'escape', 'space', 'tab', 'delete', 'return'])
    shell.setCommand('config', ['timeout', 'openUrlInNewTab', 'singleton'])
    shell.setCommand('ls')
    shell.setCommand('exit')



    return shell


window.ConsolePanel = ConsolePanel
