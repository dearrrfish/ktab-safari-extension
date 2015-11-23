'use strict'

# Includes
Strings = window.Strings or {}
Utils = window.Utils or {}
log = Utils.log
notify = Utils.notify
id = Utils.id

FakelightState =
    IDLE: 0
    WAITING_RESPONSE: 1

# Watcher and parser on omnibar input
Readline = (_inputId, _formId, _resultboxId, config = {}, callback) ->
    _completions = config.completions or {}
    _commands = config.commands or {}
    _validators = config.validators or {}

    _currentRes = {}

    _templates =
        error: _.template('<div>ERROR: <%=error%> </div>')
        preview: _.template('<% _.each(preview, function(p, index) { %><div class="preview-title"><%=p.title%></div><div class=preview-alt><%=p.alt%></div><% }) %>')

    _createPreview =
        command: (o) ->
            return { title: o.cmd, alt: o.description }


    _parseCommand = (line, options = {}) ->
        res = { error: false, requiredArgs: {}, optionalArgs: {}}
        tailSpaces = if line.match(/[^\s]+\s\s+$/) then true else false
        splits = line.trim().split(/\s+/)
        cmd = splits[0]
        return res if not cmd

        if splits.length is 1
            res.incomplete = cmd
            if options.preview
                res.preview = Utils.findMatch(cmd, _commands, _createPreview.command)
                res.error = Strings.err_unknown_command + ' - ' + cmd if not res.preview.length
        else if cmd not of _commands
            res.error = Strings.err_unknown_command + ' - ' + cmd
        else
            res.cmd = cmd
            res.rest = splits.slice(1)
            if options.parseArguments
                command = _commands[cmd]
                argRes = _parseArguments(res.rest, command.requiredArgs, command.optionalArgs)
                res.error = argRes.error
                res.requiredArgs = argRes.requiredArgs
                res.optionalArgs = argRes.optionalArgs
                if not res.error and options.preview and argRes.currentArg
                    if not argRes.currentOptional and tailSpaces
                        currentArg = command.requiredArgs[command.requiredArgs.indexOf(argRes.currentArg) + 1] or false
                    currentValue = if tailSpaces then '' else argRes.currentArgValue or ''
                    currentArg = currentArg or argRes.currentArg
                    if currentArg is not false
                        completionData = _completions[cmd]?[currentArg] ? (_completions['_all_']?[currentArg] ? false)
                        if completion
                            res.preview = Utils.findMatch(currentArgValue, completionData.completion, completionData.createPreview)  # TODO Add preview creator for different args

        # store/update current res
        _currentRes = res
        return _currentRes

    _parseArguments = (rest, requiredArgs = [], optionalArgs = [], options = {}) ->
        requiredArgs = requiredArgs.slice(0)
        optionalArgs = optionalArgs.slice(0)

        res =
            error: false
            requiredArgs: {}
            optionalArgs: {}
        res.currentArg = requiredArgs.shift()
        res.currentArgValue = ''
        res.currentOptional = if res.currentArg then false else true

        for i in [0...rest.length]
            a = rest[i]
            matchOptional = a.match(/^--\w+/)
            #log.d('readline parseArguments: current arg=' + res.currentArg + ' value=' + a)
            if not matchOptional
                # no match, required argument
                if not res.currentOptional
                    # unknown required argument
                    if not res.currentArg
                        res.error = Strings.err_unknown_required_argument + ' - ' + a
                        break
                    else
                        res.currentArgValue = res.requiredArgs[res.currentArg] = a
                        res.currentArg = requiredArgs.shift() if i < rest.length
                # no match, but optional argument's value
                else if res.currentArg? of res.optionalArgs
                    res.optionalArgs[res.currentArg].push(a)
                    res.currentArgValue = a
            else
                if not res.currentOptional and res.currentArg
                    requiredArgs.unshift(res.currentArg)
                    res.error = Strings.err_missing_required_arguments + ' - ' + requiredArgs.join(', ')
                    break
                res.currentOptional = true
                currentArg = a.slice(2)
                if currentArg not in optionalArgs
                    res.error = Strings.err_unknown_optional_argument + ' - ' + a
                    break
                else
                    res.currentArg = currentArg
                    res.optionalArgs[res.currentArg] = []

        return res


    _validateArgument = (cmd, arg, value) ->
        v = _commands[cmd]?.validators?[arg] ? _validators[arg]
        result = v[0]?(value, v[1]) if v?.length
        return result ? false


    _renderPreview = (res) ->
        $resultbox = $(id _resultboxId)
        return if not $resultbox.length
        $resultbox.empty()
        if res.error
            $resultbox.html(_templates.error({error: res.error}))
        else if res.preview.length
            $resultbox.html(_templates.preview({preview: res.preview}))


    _onChangeHandler = (e) ->
        res = { error: false, preview: [] }
        # > line = 'set ctrl+space ktab:\/\/toggleConsole --name Toggle Console --tag system ktab'
        line = $(id _inputId).val()
        #log.d('readline current line: ', line)
        pc = _parseCommand(line, {parseArguments: true, preview: true})
        if pc.error
            res.error = pc.error
        else if pc.incomplete and pc.preview?.length
            res.preview = pc.preview
        else if pc.cmd
            cmd = pc.cmd
            command = _commands[cmd]
            # final mark, determine whether future steps in command workflow
            res.final = command.final
            res.preview = if pc.preview?.length then pc.preview else [command.defaultPreview]
            # submit form when it is instant type command without parse error
            if command.instant is true
                log.d('fakelight readline: command is instant type')
                $(id _formId).submit()

        _handlers.renderPreview(res)




    _handlers =
        onChange: _onChangeHandler
        renderPreview: _renderPreview

    # public instance object
    self = {}

    # command pattern: cmd rarg1 rarg2 --opt1 val1 --opt2 val2
    self.addCommand = (c) ->
        _commands[c.cmd] =
            cmd: c.cmd
            instant: c.instant ? false
            final: c.final ? true
            description: c.description
            pattern: c.pattern
            defaultPreview: c.defaultPreview ? { title: c.description, alt: c.pattern }
            requiredArgs: c.requiredArgs ? []
            optionalArgs: c.optionalArgs ? []
            validators: c.validators ? {}

    # add completion set for command
    self.addCompletion = (arg, completion, cmd = ['_all_'], createPreview) ->
        cmd = [cmd] if not Array.isArray(cmd)
        for c in cmd
            _completions[c] = _completions[c] ? {}
            _completions[c][arg] =
                cmd: c
                arg: arg
                completion: completion
                createPreview: createPreview ? (o) ->
                    return {title: o[arg], alt: o.description or ''}

    # add argument parsers
    self.addValidator = (arg, validator) ->
        _validators[arg] = validator
        #log.d('_validators: ', _validators)

    # start to watch change
    self.watch = () ->
        $(id _inputId).on('input', _handlers.onChange)

    # handler change functions
    self.onInputChange = (handler) ->
        $input = $(id _inputId)
        $input.off('input', _handlers.onChange)
        _handlers.onChange = handler if typeof handler is 'function'
        $input.change(_handlers.onChange)

    self.onRenderPreview = (handler) ->
        _handlers.renderPreview = handler of typeof handler is 'function'


    self.get = () ->
        res = _currentRes
        cmd = res.cmd = res.cmd ? res.incomplete
        if not res.error and cmd isnt ''
            if cmd not of _commands
                res.error = Strings.err_unknown_command + ' - ' + cmd
            else
                res.request = {}
                command = _commands[cmd]
                # verify all required arguments are given in command line
                for rarg in command.requiredArgs
                    if rarg not of res.requiredArgs
                        res.error = Strings.err_missing_required_arguments + ' - ' + rarg
                        return res
                    else
                        res.request[rarg] = res.requiredArgs[rarg]

                # fill in all optional args to request
                res.request[oarg] = res.optionalArgs[oarg] for oarg of res.optionalArgs

                # validate all argument if possible
                for arg in command.requiredArgs.concat(command.optionalArgs)
                    continue if arg not of res.request
                    validateRes = _validateArgument(cmd, arg, res.request[arg])
                    continue if not validateRes
                    if validateRes.error
                        res.error = Strings.err_failed_validate_argument + '(' + validateRes.error + ') - ' + arg + ': ' + res.request[arg]
                        break
                    else
                        Utils.merge(res.request, validateRes)

        res.id = Utils.generateUUID() if not res.error
        return res


    return self



Fakelight = (config = {}) ->
    # Initial settings
    # dom ids
    _wrapperId = config.wrapperId or 'fl-container'
    _omnibarId = config.omnibarId or 'fl-omnibar'
    _omnibarCommandId = config.omnibarCommandId or 'fl-omnibar-command'
    _omnibarFormId = config.omnibarFormId or 'fl-omnibar-form'
    _omnibarInputId = config.omnibarInputId or 'fl-omnibar-input'
    _resultboxId = config.resultboxId or 'fl-resultbox'

    # Instance object
    self =
        error: false
        state: FakelightState.IDLE

    # DOM elements and verification
    _el = $(id _wrapperId)
    if not _el.length
        self.error = Strings.err_html_tag_not_found
        return self

    # Constructing elements
    _el.html('
        <div id="' + _omnibarId + '">
            <form id="' + _omnibarFormId + '">
                <div id="' + _omnibarCommandId + '">
                    <input type="text" id="' + _omnibarInputId + '" name="omnibar-command" />
                </div>
            </form>
        </div>
        <div id="' + _resultboxId + '">
        </div>
    ')

    _readline = config.readline or Readline(_omnibarInputId, _omnibarFormId, _resultboxId)

    _omnibar = $(id _omnibarId)
    _omnibarForm = $(id _omnibarFormId)
    _omnibarInput = $(id _omnibarInputId)
    _resultbox = $(id _resultboxId)

    self.eventHandlers =
        keydown: (e) ->
            return if not self.isActive()
            # TODO Fakelight behaviors: return, esc, arrow keys, etc
            switch e.keyCode
                when 27     # Esc
                    self.toggle()
                when 9      # Tab
                    e.preventDefault()

        focusout: (e) ->
            return if not self.isActive()
            _omnibar.off('focusout', self.eventHandlers.focusout)
            e.preventDefault()
            self.hide()

        submit: (e) ->
            e.preventDefault()
            res = _readline.get()
            self.hide(not res.error) if res.final
            if res.error
                notify(Strings.ttl_invalid_command, res.error, 'fakelight error message')
            else if cmd
                message =
                    reqId: res.id
                    cmd: res.cmd
                    request: res.request
                safari.self.tab.dispatchMessage('fakelightCommand', message)
                log.d('fakelight submit: send request message to global - ', message)


    self.isActive = () ->
        return true if Utils.isShown(id(_wrapperId))
        return false


    # Clear input and result
    self.clear = () ->
        _omnibarInput.val('')
        _resultbox.empty()


    # Show
    self.show = (clear = false) ->
         self.clear() if clear
         _el.show('fade', {}, 500)
         _omnibarInput.focus()
         _omnibarInput.select() if _omnibarInput.val() isnt ''
         _omnibar.focusout(self.eventHandlers.focusout)
         _omnibar.on('keydown', self.eventHandlers.keydown)


    # Hide
    self.hide = (clear = false) ->
        self.clear() if clear
        _omnibar.off('keydown', self.eventHandlers.keydown)
        _el.hide('fade', {}, 500)
        _el.blur()


    # Toggle
    self.toggle = (clear = false) ->
        if self.isActive() then self.hide(clear) else self.show(clear)


    self.validators =
        hotkey: [Utils.parseHotKeyString]   # [parserFunc, 'hotkey']
        keyhot: [Utils.parseHotKeyCode]
        url: [Utils.parseUrlString]


    self.commands =
        find: {
            enable: true
            cmd: 'find'
            instant: true
            final: false
            pattern: Utils.escapeHtml('find <type> [--title <title>] [--tags <tag1> <tag2> ...]')
            description: 'Search for bookmarks.'
            requiredArgs: ['type']
            optionalArgs: ['title', 'tags']
        }

        set: {
            enable: true
            cmd: 'set'
            instant: false
            final: true
            pattern: Utils.escapeHtml('set <hotkey> <url> [--name <name>] [--tags <tag1> <tag2> ...]')
            description: 'Set hotkey binding'
            requiredArgs: ['hotkey', 'url']
            optionalArgs: ['name', 'tags']
        }

        unset: {
            enable: true
            cmd: 'unset'
            instant: false
            final: true
            pattern: Utils.escapeHtml('unset <hotkey>')
            description: 'Unset hotkey binding'
            requiredArgs: ['hotkey']
            optionalArgs: []
        }



    for cmd of self.commands
        _readline.addCommand(self.commands[cmd]) if self.commands[cmd].enable

    _readline.addCompletion('type', [
        {type: 'bookmark', description: 'Search for bookmarks'}
        {type: 'tag', description: 'Search for tags'}
        {type: 'hotkey', description: 'Search for hotkey bindings'}
    ], ['find'])

    _readline.addValidator(arg, self.validators[arg]) for arg of self.validators

    _readline.watch()

    $(id _omnibarFormId).submit(self.eventHandlers.submit)

    return self


window.Fakelight = Fakelight


window.Messanger = window.Messanger or {}
window.Messanger.handleFakelight = (e) ->
    refId = e.message.refId
    cmd = e.message.cmd
    results = e.message.results
    switch cmd
        when 'find'
            notify('find command successfully return ' + results.length + ' bookmarks.')
            log.d('fakelight.find get ' + results.length + ' bookmarks.')

