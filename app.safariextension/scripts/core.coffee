'use strict'

Utils = window.Utils
log = Utils.log or { i: -> e: -> d: -> }

Messanger = window.Messanger or {}
ConsolePanel = window.ConsolePanel or {}

config = {}
config.shell =
    name: 'KTab.ConsolePanel'
    shellViewId: 'shell-view'
    shellPanelId: 'shell-panel'
    inputId: 'shell-cli'

shell = ConsolePanel(config.shell)

# DOM ready
$ ->
    # kTab keyup/down handlers
    onKeyUp = (e) ->
        pressedKey = $('.k' + e.keyCode)
        pressedKey.removeClass('pressed')
        return

    onKeyDown = (e) ->
        pressedKey = $('.k' + e.keyCode)
        pressedKey.addClass('pressed');
        return if not pressedKey.hasClass('key') or (shell and shell.isActive())
        fkey = 0
        fkey += 1 if e.ctrlKey
        fkey += 2 if e.altKey
        fkey += 4 if e.shiftKey
        safari.self.tab.dispatchMessage('pressedKeyNavigate', { key: e.keyCode, fkey: fkey })
        return

    onKeyPressed = (e) ->

    # Add event listener
    $(window).on('keyup', onKeyUp)
    $(window).on('keydown', onKeyDown)


    ###
    ConsolePanel actions
    ###
    shell.$el = $('#' + config.shell.shellPanelId)
    shell.$el.resizable({ handles: 's' })

    shell.activateAndShow = () ->
        shell.activate()
        shell.$el.slideDown()
        shell.$el.focus()

    shell.deactivateAndHide = () ->
        shell.$el.slideUp()
        shell.$el.blur()
        shell.deactivate()

    shell.onEOT(shell.deactivateAndHide)
    shell.onCancel(shell.deactivateAndHide)


    doToggleConsole = () ->
        if (shell.isActive())
            shell.deactivateAndHide()
        else
            shell.activateAndShow()

    # Message handlers
    Messanger.handleEvent = (e) ->
        log.d('handleMessage: ', e)
        switch e.name
            when 'toggleConsole'
                doToggleConsole()
            when 'consoleResponse'
                Messanger.handleConsoleEvent?(e)

    safari.self.addEventListener('message', Messanger.handleEvent, false)
