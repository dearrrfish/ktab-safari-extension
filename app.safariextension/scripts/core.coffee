'use strict'

Utils = window.Utils
log = Utils.log
id = Utils.id

FakeLight = window.FakeLight

config = {}

config.about =
    wrapperId: 'about-info-wrapper'
    signWrapperId: 'about-sign-wrapper'


# DOM ready
$ ->
    flight = Fakelight()
    if flight.error
        alert(flight.error)
    $about = $('#' + config.about.wrapperId)

    # kTab keyup/down handlers
    onKeyUp = (e) ->
        pressedKey = $('.k' + e.keyCode)
        pressedKey.removeClass('pressed')
        return

    onKeyDown = (e) ->
        pressedKey = $('.k' + e.keyCode)
        pressedKey.addClass('pressed');
        # do nothing more if function key or console is open
        if flight?.isActive()
            return
        # close if about page is open
        else if Utils.isShown($about)
            e.preventDefault()
            doToggleAbout()
        # otherwise, send message to extension
        else if pressedKey.hasClass('key')
            fkey = 0
            fkey += 1 if e.ctrlKey
            fkey += 2 if e.altKey
            fkey += 4 if e.shiftKey
            safari.self.tab.dispatchMessage('pressedKeyNavigate', { key: e.keyCode, fkey: fkey })


    # Add event listener
    $(window).on('keyup', onKeyUp)
    $(window).on('keydown', onKeyDown)

    # About/Help overlay
    doToggleAbout = () ->
        $about.toggle("clip", {}, 500)

    $('#' + config.about.signWrapperId).click(doToggleAbout)

    # Message handlers
    handleEvent = (e) ->
        log.d('handleMessage: ', e)
        switch e.name
            when 'toggleAbout'
                doToggleAbout()
            when 'toggleFakelight'
                flight.toggle()
            when 'fakelight'
                Messanger.handleFakelight?(e)


    safari.self.addEventListener('message', handleEvent, false)
