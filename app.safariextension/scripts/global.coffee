'use strict'

Utils = window.Utils
log = window.Utils.log

# Global object
kTab =
    version: safari.extension.bundleVersion
    browserWindows: safari.application.browserWindows
    mainUrl: safari.extension.baseURI + 'main.html'
    trigger: false
    configs: {
        singleton: {
            description: "Only one instance in window"
            type: 'boolean'
            default: true
        }
        openUrlInNewTab: {
            description: "Open link in new tab"
            type: 'boolean'
            default: false
        }
        timeout: {
            description: "Timeout (ms) of default trigger"
            type: 'int'
            default: 500
        }
        logLevel: {
            description: "Logging level in browser console"
            type: 'string'
            default: 'error'
        }
    }

# Settings

kTab.loadSettings = () ->
    kTab.settings =
        singleton: safari.extension.settings.singleton || kTab.configs.singleton.default
        openUrlInNewTab: safari.extension.settings.openUrlInNewTab || kTab.configs.openUrlInNewTab.default
        timeout: safari.extension.settings.timeout || kTab.configs.timeout.default
        logLevel: safari.extension.settings.logLevel || kTab.configs.logLevel.default
        actions: safari.extension.settings.actions || {
            toggleConsole: true
            toggleAbout: true
            # ...
        }

kTab.saveSettings = (option) ->
    if option?
        safari.extension.settings[option] = kTab.settings[option] if option of kTab.settings
    else
        for opt in kTab.settings
            safari.extension.settings[opt] = kTab.settings[opt]


# Default mapping
# -- fkey_state: use binary number by sequence <shift><alt><ctrl>.
# -- e.g. 6 => 110 => pressed <alt> and <shift>
kTab.defaultBindings =
    '86': {
        '0': {name: 'V2EX', type: 'url', url: 'https://v2ex.com'}
    }
    '192': {
        '4': {name: 'Toggle Console', type: 'action', action: 'toggleConsole', url: 'ktab://toggleConsole'}
    }

kTab.loadBindings = () ->
    kTab.settings.bindings = safari.extension.settings.bindings or kTab.defaultBindings

kTab.updateBindings = () ->
    safari.extension.settings.bindings = kTab.settings.bindings

# Define commands
kTab.commands =
    # Init
    init: () ->
        @checkVersion()
        @loadSettings()
        return

    # Check and store version
    checkVersion: () ->
        if not localStorage['version']?
            safari.extension.settings = {}
            localStorage['version'] = kTab.version

    # Load settings
    loadSettings: () ->
        kTab.loadSettings()
        kTab.loadBindings()

    # Show main(navigator) page
    showMain: (e) ->
        if kTab.settings.singleton or e.target not instanceof SafariBrowserTab
            @showUrl(kTab.mainUrl, e)
        else
            e.target.url = kTab.mainUrl

    # Get existing binding
    getBindingByHotKey: (key, fkey) ->
        bindings = kTab.settings.bindings
        return bindings[key]?[fkey] or null

    # Get all bindings on key
    getBindingsOnKey: (key) ->
        return kTab.settings.bindings[key] or null

    # Set binding
    setBinding: (req) ->
        bindings = kTab.settings.bindings or {}
        bindings[req.key] = bindings[req.key] or {}
        binding = {name: req.name, type: req.type, url: req.url}
        if req.type is 'action'
            return 'ERROR<setBinding|Action>: Invalid or disallowed action. - [' + req.dest + ']' if not kTab.settings.actions[req.dest]
            binding.action = req.dest
        bindings[req.key][req.fkey] = binding
        kTab.updateBindings()
        log.d('setBinding: ', [req.key, req.fkey, binding])
        return 'OK: Set ' + req.type + ' binding successfully!'

    # Unset binding by hotkey
    unsetBinding: (req) ->
        bindings = kTab.settings.bindings or {}
        if bindings[req.key]?[req.fkey]
            delete bindings[req.key][req.fkey]
            delete bindings[req.key] if Object.keys(bindings[req.key]).length is 0
            kTab.updateBindings()
            return 'OK: Unset binding successfully!'
        else
            return 'KO: Unable to locate binding by given hotkey.'

    # Show all bindings
    showBindings: (req) ->
        bindings = kTab.settings.bindings or {}
        log.d('Global|showBindings(): ', bindings);
        results = []
        for own key of bindings
            for own fkey of bindings[key]
                results.push({key: key, fkey: fkey, binding: bindings[key][fkey]})

        res = {results: results}
        res.callback = req.callback if req.callback?
        return res

    # Set app configuration
    setOption: (req) ->
        return 'KO: Unknown option. - [' + req.option + ']' if req.option not of kTab.configs
        defaults = kTab.configs[req.option]
        res = 'OK: ' + defaults.description + ': '

        value = Utils.parseValue(defaults.type, req.value, req.selects)
        if value.error
            res = 'KO: Parse option value error. - [' + value.error + ']'
        else
            res += value[defaults.type]
            kTab.settings[req.option] = value[defaults.type]
            kTab.saveSettings(req.option)
        return res


    # Message actions hub
    exec: (found, e) ->
        return log.e('exec: missing action name in bindings.') if not found.type
        switch(found.type)
            when 'url'
                @showUrl(found.url, e)
            when 'action'
                @doAction(found.action, e)

    # Execute action
    doAction: (action, options..., e) ->
        return log.e('execAction: missing action name in settings.') if not action
        switch action
            when 'toggleConsole' then @doToggleConsole(e)
            when 'toggleAbout' then @doToggleAbout(e)

    # Toggle console
    doToggleConsole: (e) ->
        e.target.page.dispatchMessage('toggleConsole')

    # Toggle about overlay
    doToggleAbout: (e) ->
        e.target.page.dispatchMessage('toggleAbout')

    # Show/open tab with given url
    showUrl : (url, options..., e) ->
        return log.e('showUrl: missing url in settings.') if not url

        # Open in new tab if trigger from settings
        openUrlInNewTab = true if not e?.target or e.target instanceof SafariExtensionSettings
        openUrlInNewTab = (options?.openUrlInNewTab ? kTab.settings.openUrlInNewTab) if not openUrlInNewTab

        targetWindows = if url is kTab.mainUrl then [safari.application.activeBrowserWindow] else safari.application.browserWindows
        # Find exist tab with given url
        for window in targetWindows
            tabs = window.tabs
            for tab in tabs
                if tab.url is url
                    window.activate()
                    tab.activate()
                    e.target.close() if e?.target instanceof SafariBrowserTab
                    return

        if not openUrlInNewTab and e?.target instanceof SafariBrowserTab
            e.target.url = url
        else if not openUrlInNewTab and safari.application.activeBrowserWindow.activeTab?
            safari.application.activeBrowserWindow.activeTab.url = url
        else
            # If url not found, then open a new tab
            newTab = safari.application.activeBrowserWindow.openTab()
            newTab.url = url
            newTab.browserWindow.activate()
            newTab.activate()
        return


# Initialize
kTab.commands.init()

######################

# Event Handlers
handleSettingsChange = (e) ->
    log.d('Received settings.change event: ', e)
    switch e.key
        when 'showMain'
            if e.newValue is true
                safari.extension.settings.showMain = false
                kTab.commands.showMain(e)
    return

handleOpen = (e) ->
    if e.target instanceof SafariBrowserTab
        kTab.trigger = false
        e.target.addEventListener('beforeNavigate', handleBeforeNavigate, false)
        setTimeout(() ->
            e.target.removeEventListener('beforeNavigate', handleBeforeNavigate, false)
            if not kTab.trigger
                log.d('beforeNavigate NOT trigger.', e)
                e.preventDefault()
                kTab.commands.showMain(e)
            return
        , kTab.settings.timeout)
    return

handleBeforeNavigate = (e) ->
    kTab.trigger = true
    e.target.removeEventListener('beforeNavigate', handleBeforeNavigate, false)
    log.d('beforeNavigate triggers.', e)
    # TODO e.url is null, which could be safari top sites, bookmarks, or pages of extensions
    if e.url is kTab.mainUrl
        kTab.commands.showMain(e)
    return

handleMessage = (e) ->
    log.d('Received message: ', e)
    switch e.name
        when 'pressedKeyNavigate'
            found = kTab.commands.getBindingByHotKey(e.message.key, e.message.fkey)
            log.d('Key binding: ', found)
            return if not found?
            kTab.commands.exec(found, e)
        when 'consoleRequest'
            req = e.message.request
            res = null
            switch (e.message.cmd)
                when 'setBinding'
                    res = kTab.commands.setBinding(req)
                when 'unsetBinding'
                    res = kTab.commands.unsetBinding(req)
                when 'showBindings'
                    res = kTab.commands.showBindings(req)
                when 'setOption'
                    res = kTab.commands.setOption(req)
            e.target.page.dispatchMessage('consoleResponse', {cmd: e.message.cmd, response: res})
    return

# Bind listener to Safari
safari.extension.settings.addEventListener('change', handleSettingsChange, false)
safari.application.addEventListener('open', handleOpen, true)
safari.application.addEventListener('message', handleMessage, false);

log.i('Thanks for using kTab!')
