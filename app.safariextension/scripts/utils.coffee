_accessSettings = if safari?.extension?.settings? then true else false

log =
    levels: ['info', 'error', 'debug']

    setLevel: (level) ->
        return if level not in @levels
        localStorage['_log_level'] = level

    log: (level, msg, arg) ->
        if _accessSettings
            config = safari.extension.settings.logLevel
        else
            config = localStorage['_log_level'] ? 'error'

        return if @levels.indexOf(config) < @levels.indexOf(level)
        _level = '%c[' + level.toUpperCase() + ']'
        _level_css = 'font-weight: bold;' + (if level is 'error' then 'color: red' else '')
        _msg = '%c' + (if typeof msg is 'string' then msg else '')
        _msg_css = '' + (if level is 'error' then 'color: red' else '')
        _arg = arg ? ''
        console.log(_level + _msg, _level_css, _msg_css, _arg)

    i: (msg, arg) ->
        @log('info', msg, arg)
    e: (msg, arg) ->
        @log('error', msg, arg)
    d: (msg, arg) ->
        @log('debug', msg, arg)

#arr_eq = (arr1, arr2) ->
    #return false if arr1.length isnt arr2.length
    #return arr1.every((e) ->
        #return e in arr2
    #)


reverseMap = (o) ->
    ro = {}
    ro[v] = k for own k, v of o
    return ro

keyCode =
    '0': 48
    '1': 49
    '2': 50
    '3': 51
    '4': 52
    '5': 53
    '6': 54
    '7': 55
    '8': 56
    '9': 57
    space: 32
    '=': 187
    a: 65
    b: 66
    c: 67
    d: 68
    e: 69
    f: 70
    g: 71
    h: 72
    i: 73
    j: 74
    k: 75
    l: 76
    m: 77
    n: 78
    o: 79
    p: 80
    q: 81
    r: 82
    s: 83
    t: 84
    u: 85
    v: 86
    w: 87
    x: 88
    y: 89
    z: 90
    '-': 189
    '.': 190
    '/': 191
    ',': 188
    '`': 192
    '[': 219
    '\\': 220
    ']': 221
    '\'': 222
    tab: 9
    return: 13
    shift: 16
    ctrl: 17
    alt: 18
    capslock: 20
    escape: 27
    delete: 8

codeKey = reverseMap(keyCode)

fkeyVal =
    escape: false
    tab: false
    ctrl: 1
    alt: 2
    shift: 4
    cmd: false
    delete: false
    return: false
    capslock: false

getKeyCode = (key) ->
    return false if key not of keyCode
    result = [keyCode[key]]
    result.push(fkeyVal[key]) if key of fkeyVal
    return result

getCodeKey = (code, fkey = false) ->
    if not fkey
        return codeKey[code] ? false
    switch code
        when 1, '1'
            return 'ctrl'
        when 2, '2'
            return 'alt'
        when 3, '3'
            return 'ctrl+alt'
        when 4, '4'
            return 'shift'
        when 5, '5'
            return 'ctrl+shift'
        when 6, '6'
            return 'ctrl+alt+shift'
        when 0, '0'
            return ''
        else
            return false


# Parsers

parseValue = (type, value, selects = []) ->
    result = {error: false}
    result.error = 'invalid value out of restrictions - ' + selects if selects.length and value not in selects
    switch type
        when 'bolean'
            switch value
                when 'true', 'yes', 'on', '1'
                    result.boolean = true
                when 'false', 'no', 'off', '0'
                    result.boolean = false
                else
                    result.error = 'unknown boolean value - ' + value
        when 'int'
            n = parseInt(value)
            if typeof n is 'number' and not isNaN(n)
                result.int = n
            else
                result.error = 'parse integer error - ' + value
        when 'string'
            result.string = value
        else
            result.error = 'unknown value type - ' + type
    return result

parseArguments = (args, defaults = [], require = true) ->
    result = {error: false}
    currentArgName = ''
    defaultsArgs = []
    for arg in args
        if currentArgName and result[currentArgName]
            result.error = 'duplicate argument given - `' + currentArgName + '`'
            break

        if arg.match(/^--/)
            result[currentArgName] = true if currentArgName
            currentArgName = arg.slice(2)
            if not currentArgName
                result.error = 'empty argument name given'
                break
        else if currentArgName
            result[currentArgName] = arg
            currentArgName = ''
        else
            defaultsArgs.push(arg)

    for d in defaults
        if not result[d]
            if defaultsArgs.length
                result[d] = defaultsArgs.shift()
            else if require
                result.error = 'missing required arguments - `' + d + '`'
                break

    return result


parseHotKeyString = (hotkey) ->
    result = {error: false, hotkey: hotkey}
    fkeyMap = {}
    fkey = 0
    key = false
    keys = hotkey.split('+')
    for k in keys
        k = k.toLowerCase()
        kc = Utils.getKeyCode(k)
        if not kc
            result.error = 'unknown/invalid key - `' + k + '`'
        else if kc.length > 1
            if kc[1]
                fkeyMap[k] = kc[1]
            else
                result.error = 'function key is disallowed - [ ' + k + ' ]'
        else if key
            result.error = 'only one main key is allowed'
        else
            key = kc[0]
        break if result.error
    return result if result.error
    fkey += fkeyMap[fk] for fk of fkeyMap
    if not key
        result.error = 'main key is missing'
    else
        result.key = key
        result.fkey = fkey

    return result


parseUrlString = (url) ->
    result = {error: false, url: url}
    protocol = (url.match(/.*:\/\//) or [''])[0].slice(0, -3).toLowerCase()
    if not protocol
        result.error = 'missing protocol in url schema - `' + url + '`'
    else
        dest = url.slice(protocol.length + 3)
        result.error = 'missing destination in url schema - `' + url + '`' if not dest
    result.protocol = protocol
    result.dest = dest
    return result


parseHotKeyCode = (key, fkey) ->
    result = {error: false, key: key, fkey: fkey}
    keyString = Utils.getCodeKey(key)
    fkeyString = Utils.getCodeKey(fkey, true)
    if keyString is false or fkeyString is false
        result.error = 'incorrect hotkey code given - `' + [key, fkey] + '`'
    else
        result.string = (if fkeyString then fkeyString + '+' else '') + keyString
    return result


parseBindingObject = (binding) ->
    result = {error: false, binding: binding}
    if not binding.type or not binding.url
        result.error = 'incorrect binding information - `' + JSON.stringify(binding) + '`'
    else if binding.type not in ['action', 'url']
        result.error = 'unknown binding type - `' + binding.type + '`'
    return result if result.error

    result.string = '[' + binding.type.toUpperCase() + ']  ' + (binding.name or 'NO_NAME') + (if binding.type is 'url' then '  (' + binding.url + ')' else '')
    return result



window.Utils =
    log: log
    reverseMap: reverseMap

    getKeyCode: getKeyCode
    getCodeKey: getCodeKey

    parseValue: parseValue
    parseArguments: parseArguments
    parseHotKeyString: parseHotKeyString
    parseHotKeyCode: parseHotKeyCode
    parseUrlString: parseUrlString
    parseBindingObject: parseBindingObject

