Utils = window.Utils
log = Utils.log

# https://developer.apple.com/library/safari/documentation/iPhone/Conceptual/SafariJSDatabaseGuide/UsingtheJavascriptDatabase/UsingtheJavascriptDatabase.html#//apple_ref/doc/uid/TP40007256-CH3-SW9
DatabaseError =
    NON_DB_ERROR: 0
    OTHER_DB_ERROR: 1
    INVALID_STATE_ERR: 2
    RESULT_SET_TOO_LARGE: 3
    STORAGE_LIMIT_EXCEEDED: 4
    LOCK_CONTENTION_ERROR: 5
    CONSTRAINT_FAILURE: 6


window.ExtensionDatabase = window.ExtensionDatabase or {}

ExtensionDatabase = (options = {}) ->
    try
        if (not window.openDatabase)
            log.e('db: Not supported by your browser.')
            return

        _name = options.name ? 'ktab-db'
        _version = options.version ? '1.0'
        _displayName = options.displayName ? 'kTab Database'
        _maxSize = options.maxSize ? 65535
        _isErrorFatal = options.isErrorFatal ? true
        _db = openDatabase(_name, _version, _displayName, _maxSize)
        log.d('db: open connection to instance `' + _name  + '`', [_version, _displayName, _maxSize])

    catch e
        if e is DatabaseError.INVALID_STATE_ERR  # version number not match
            log.e('db: Invalid databse version.')
        else
            log.e('db: ' + e)
        return

    _ForceFatalErrorHandler = (tr, e) ->
        log.e('db (' + e.code + '): ' + e.message)
        log.e('db: fatal error detected (forced), transaction rolls back.')
        return true # fatal transaction error

    _ForceIgnoreErrorHandler = (tr, e) ->
        log.e('db (' + e.code + '): ' + e.message)
        log.e('db: error is ignored (forced), transaction continues.')
        return false

    _errorHandler = (tr, e) ->
        log.e('db (' + e.code + '): ' + e.message)
        if _isErrorFatal
            log.e('db: fatal error detected, transaction rolls back.')
        else
            log.e('db: error is ignored, transaction continues.')
        return _isErrorFatal

    _nullDataHandler = (tr, e) ->

    _nullHandler = () ->

    _handlers =
        forceFatalError: _ForceFatalErrorHandler
        forceIgnoreError: _ForceIgnoreErrorHandler
        error: _errorHandler
        nullData: _nullDataHandler
        null: _nullHandler


    _onError = (handler) ->
        _handlers.error = handler

    _prepare = (queries...) ->
        res = {error: false, queries: []}

        for query in queries
            sql = query.sql ? ''
            inputs = query.data ? []
            # validate query string
            if not sql
                res.error = 'no sql query string provided'
            else
                fields = sql.match(/\?/g) ? []
                if fields.length isnt data.length
                    res.error = 'mismatch between field(s) and value(s) - `' + sql + '` [' + inputs + ']'
            break if res.error
            # prepare statement and add to result
            stmt =
                sql: sql
                data: data
                done: query.done ? _handlers.nullData
                error: ((forceFatal) ->
                    switch forceFatal
                        when true
                            return _handlers.forceFatalError
                        when false
                            return _handlers.forceIgnoreError
                        else
                            return _handlers.error
                )(query.error)
            res.queries.push(stmt)

        return res


    _execute = (prepared, fail, success) ->
        if prepared.error
            fail?({code: DatabaseError.OTHER_DB_ERROR, message: prepare.error})
        else if not prepared.queries.length
            fail?({code: DatabaseError.NON_DB_ERROR, message: 'empty query set provided'})
        else
            _db.transaction((tr) ->
                tr.executeSql(q.sql, q.inputs, q.done, q.error) for q in queries
            , success, fail)

    self =
        tables: ['bookmarks', 'tags', 'link-bookmark-tag', 'hotkeys']

    self.sqls =
        dropTable: 'DROP TABLE ?;'
        createTableBookmarks: 'CREATE TABLE IF NOT EXISTS bookmarks(id INTEGER)'


    self.dropTables = () ->
        prepared = _prepare(
            {sql: 'DROP TABLE bookmarks;'}
            {sql: 'DROP TABLE tags;'}
            {sql: 'DROP TABLE link-bookmark-tag;'}
            {sql: 'DROP TABLE hotkeys;'}
        )
        _execute(prepared)


    self.init = (reset = false) ->
        # drop all tables
        self.dropTables if reset


    return self

