'use strict'

Utils = window.Utils
Strings = window.Strings
log = window.Utils.log

# Global object
KTab =
    version: safari.extension.bundleVersion
    browserWindows: safari.application.browserWindows
    mainUrl: safari.extension.baseURI + 'main.html'
    trigger: false
    db: null

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
            default: 'debug'
        }
    }

# Settings

KTab.loadSettings = () ->
    safari.extension.settings.logLevel = safari.extension.settings.logLevel ? 'debug';

    KTab.settings =
        singleton: safari.extension.settings.singleton or KTab.configs.singleton.default
        openUrlInNewTab: safari.extension.settings.openUrlInNewTab or KTab.configs.openUrlInNewTab.default
        timeout: safari.extension.settings.timeout or KTab.configs.timeout.default
        logLevel: safari.extension.settings.logLevel or KTab.configs.logLevel.default


KTab.saveSettings = (option) ->
    if option?
        safari.extension.settings[option] = KTab.settings[option] if option of KTab.settings
    else
        for opt in KTab.settings
            safari.extension.settings[opt] = KTab.settings[opt]


# Default mapping
# -- fkey_state: use binary number by sequence <shift><alt><ctrl>.
# -- e.g. 6 => 110 => pressed <alt> and <shift>
KTab.defaultBindings =
    '86': {
        '0': {name: 'V2EX', type: 'url', url: 'https://v2ex.com'}
    }
    '32': {
        '1': {name: 'Fakelight', type: 'action', action: 'toggleFakelight', url: 'ktab://toggleFakelight'}
    }

KTab.loadBindings = () ->
    KTab.settings.bindings = safari.extension.settings.bindings or KTab.defaultBindings

KTab.updateBindings = () ->
    safari.extension.settings.bindings = KTab.settings.bindings


# Define commands
KTab.commands =
    # Init
    init: () ->
        try
            if not localStorage['version']?
                safari.extension.settings = {}
                localStorage['version'] = KTab.version

            KTab.loadSettings()
            KTab.loadBindings()
            KTab.db = KTabDatabase()
            KTab.db.init({debug: true})
        catch e
            log.e('initialization failed (' + e.message + ')')

    # Show main(navigator) page
    showMain: (e) ->
        if KTab.settings.singleton or e.target not instanceof SafariBrowserTab
            @showUrl(KTab.mainUrl, e)
        else
            e.target.url = KTab.mainUrl

    # Get existing binding
    getBindingByHotKey: (key, fkey) ->
        bindings = KTab.settings.bindings
        return bindings[key]?[fkey] or null

    # Get all bindings on key
    getBindingsOnKey: (key) ->
        return KTab.settings.bindings[key] or null

    # Set binding
    setBinding: (req) ->
        bindings = KTab.settings.bindings or {}
        bindings[req.key] = bindings[req.key] or {}
        binding = {name: req.name, type: req.type, url: req.url}
        if req.type is 'action'
            #return 'ERROR<setBinding|Action>: Invalid or disallowed action. - [' + req.dest + ']' if not KTab.settings.actions[req.dest]
            binding.action = req.dest
        bindings[req.key][req.fkey] = binding
        KTab.updateBindings()
        log.d('setBinding: ', [req.key, req.fkey, binding])
        return 'OK: Set ' + req.type + ' binding successfully!'

    # Unset binding by hotkey
    unsetBinding: (req) ->
        bindings = KTab.settings.bindings or {}
        if bindings[req.key]?[req.fkey]
            delete bindings[req.key][req.fkey]
            delete bindings[req.key] if Object.keys(bindings[req.key]).length is 0
            KTab.updateBindings()
            return 'OK: Unset binding successfully!'
        else
            return 'KO: Unable to locate binding by given hotkey.'

    # Show all bindings
    showBindings: (req) ->
        bindings = KTab.settings.bindings or {}
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
        return 'KO: Unknown option. - [' + req.option + ']' if req.option not of KTab.configs
        defaults = KTab.configs[req.option]
        res = 'OK: ' + defaults.description + ': '

        value = Utils.parseValue(defaults.type, req.value, req.selects)
        if value.error
            res = 'KO: Parse option value error. - [' + value.error + ']'
        else
            res += value[defaults.type]
            KTab.settings[req.option] = value[defaults.type]
            KTab.saveSettings(req.option)
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
            when 'toggleFakelight' then @doToggleFakelight(e)

    # Toggle console
    doToggleConsole: (e) ->
        e.target.page.dispatchMessage('toggleConsole')

    # Toggle about overlay
    doToggleAbout: (e) ->
        e.target.page.dispatchMessage('toggleAbout')

    # Toggle Fakeligh
    doToggleFakelight: (e) ->
        e.target.page.dispatchMessage('toggleFakelight')

    # Show/open tab with given url
    showUrl : (url, options..., e) ->
        return log.e('showUrl: missing url in settings.') if not url

        # Open in new tab if trigger from settings
        openUrlInNewTab = true if not e?.target or e.target instanceof SafariExtensionSettings
        openUrlInNewTab = (options?.openUrlInNewTab ? KTab.settings.openUrlInNewTab) if not openUrlInNewTab

        isTargetMain = url is KTab.mainUrl
        targetWindows = if isTargetMain then [safari.application.activeBrowserWindow] else safari.application.browserWindows
        # Find exist tab with given url
        for window in targetWindows
            tabs = window.tabs
            for tab in tabs
                if tab.url is url or (isTargetMain and tab.url.match(KTab.mainUrl)?.index is 0)
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

    ajaxPreviewUrl: (url, callback) ->
        res = {error: false}
        $.ajax({
            url: url
            success: (data) ->
                $html = $.parseHTML(data)
                res.title = $html.filter('title').text()
                # get more...
            error: () ->
                res.error = Strings.err_ajax_preview_url_failed + ' - ' + url
            complete: () ->
                callback?(res)
        })

KTab.findBookmark = (req, callback) ->
    


KTab.setInternalHotkey = (req, callback) ->
    



# Fakelight handler
KTab.fakelight =
    enabled: true    # TODO add switch option

    # keywords of commands
    commands:
        find: (id, req, e) ->
            KTab.db.retrieveAllBookmarks((results) ->
                e.target.page.dispatchMessage('fakelight', {refId: id, cmd: 'find', results: results})
            )

        set: (id, req, e) ->
            # protocol = 'ktab', is an action other than web url
            if req.protocol is 'ktab'
                #res = KTab.setInternalHotkey(req)
            else
                #res = KTab.setBookmarkHotkey(req)
            return res


    exec: (e) ->
        if e.message.cmd of @commands
            @commands[e.message.cmd]?(e.message.reqId, e.message.request, e)
        else
            log.e(Strings.err_internal_coding_error + ' - [no such command - `' + e.message.cmd + '`]')


# Initialize
KTab.commands.init()

######################

# Event Handlers
handleSettingsChange = (e) ->
    log.d('Received settings.change event: ', e)
    switch e.key
        when 'showMain'
            if e.newValue is true
                safari.extension.settings.showMain = false
                KTab.commands.showMain(e)
    return

handleOpen = (e) ->
    if e.target instanceof SafariBrowserTab
        KTab.trigger = false
        e.target.addEventListener('beforeNavigate', handleBeforeNavigate, false)
        setTimeout(() ->
            e.target.removeEventListener('beforeNavigate', handleBeforeNavigate, false)
            if not KTab.trigger
                log.d('beforeNavigate NOT trigger.', e)
                e.preventDefault()
                KTab.commands.showMain(e)
            return
        , KTab.settings.timeout)
    return

handleBeforeNavigate = (e) ->
    KTab.trigger = true
    e.target.removeEventListener('beforeNavigate', handleBeforeNavigate, false)
    log.d('beforeNavigate triggers.', e)
    # TODO e.url is null, which could be safari top sites, bookmarks, or pages of extensions
    if e.url is KTab.mainUrl
        KTab.commands.showMain(e)
    return

handleMessage = (e) ->
    log.d('Received message: ', e)
    switch e.name
        when 'pressedKeyNavigate'
            found = KTab.commands.getBindingByHotKey(e.message.key, e.message.fkey)
            log.d('Key binding: ', found)
            return if not found?
            KTab.commands.exec(found, e)

        when 'fakelightCommand'
            if KTab.fakelight.enabled
                KTab.fakelight.exec?(e)
            else
                log.e('Fakelight is disabled.')

        when 'consoleRequest'
            req = e.message.request
            res = null
            switch (e.message.cmd)
                when 'setBinding'
                    res = KTab.commands.setBinding(req)
                when 'unsetBinding'
                    res = KTab.commands.unsetBinding(req)
                when 'showBindings'
                    res = KTab.commands.showBindings(req)
                when 'setOption'
                    res = KTab.commands.setOption(req)
            e.target.page.dispatchMessage('consoleResponse', {cmd: e.message.cmd, response: res})
    return

# Bind listener to Safari
safari.extension.settings.addEventListener('change', handleSettingsChange, false)
safari.application.addEventListener('open', handleOpen, true)
safari.application.addEventListener('message', handleMessage, false);

log.i('Thanks for using kTab!')
log.d('current mode: debug')
