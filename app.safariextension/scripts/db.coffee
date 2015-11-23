'use strict'

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

    # Custom errors
    PARSE_SQL_COMPONENTS_ERROR: 101
    MISSING_REQUIRED_INPUTS: 102
    EXECUTE_SQL_ERROR: 103




window.KTabDatabase = (options = {}) ->
    try
        if (not window.openDatabase)
            log.e('db: Not supported by your browser.')
            return

        _name = options.name ? 'kTabDB'
        _version = options.version ? '1.0'
        _displayName = options.displayName ? 'kTab Database'
        _maxSize = options.maxSize ? 65536  # default 5M
        log.d('db: open connection to instance `' + _name  + '`', [_version, _displayName, _maxSize])
        _db = html5sql.openDatabase(_name, _displayName, _maxSize)
        log.d('db: connected to database.')

    catch e
        if e is DatabaseError.INVALID_STATE_ERR  # version number not match
            log.e('db: Invalid databse version.')
        else
            log.e('db: unknown error - ' + e)
        return


    # Describes of Tables
    _tables = options.tables ? {
        'bookmarks': ['id', 'url', 'title', 'favicon', 'visit', 'favorite', 'created']
        'tags': ['id', 'name', 'created']
        'link-bookmark-tag': ['bookmark_id', 'tag_id', 'created']
        'hotkeys': ['key', 'fkey', 'bookmark_id', 'hotkey_string', 'created']
    }


    # Helper to prepare components for sql object
    _prepareSql = (command, table, item = {}, options = {}) ->
        res = {error: false}
        # shared components pre-parsing
        # make sure table is defined in code
        fs = _tables[table]
        if not fs?.length
            res.error =
                code: DatabaseError.PARSE_SQL_COMPONENTS_ERROR
                message: 'failed to lookup table fields - `' + table + '`'
            return res

        # if allows to generate default uuid for fields
        if options.uuids?.length
            for f in options.uuids
                item[f] = item[f] ? Utils.generateUUID()
        # if allows to generate default timestamp for fields
        if options.timestamps?.length
            for f in options.timestamps
                item[f] = item[f] ? Utils.formatDate()
        # check all required fields are set
        if options.required?.length
            for f in options.required
                if not item[f]
                    log.e('db add: missing required field input when building sql object - ' + f, item)
                    res.error =
                        code: DatabaseError.MISSING_REQUIRED_INPUTS
                        message: 'missing required field input when building sql object - ' + f
                    return res

        # command specific parsing
        switch command
            when 'INSERT'
                fields = []
                placeholders = []
                data = []

                (if f of item
                    fields.push(f)
                    placeholders.push('?')
                    data.push(item[f])
                ) for f in fs

                if not fields.length
                    res.error =
                        code: PARSE_SQL_COMPONENTS_ERROR
                        message: 'no eligible fields provided for INSERT statement'
                    return res
                else
                    res.sql = 'INSERT INTO `' + table + '` (' + fields.join(',') + ')' + ' VALUES (' + placeholders.join(',') + ');'
                    res.data = data

            when 'SELECT'
                # base SELECT statement
                sql = 'SELECT '
                if item.fields?.length
                    fields = []
                    (fields.push(f) if f in _tables[tbl]) for f in options.fields
                    sql += fields.join(',') if fields.length
                else
                    sql += '*'
                # TABLE
                sql += ' FROM `' + table + '`'
                # WHERE condition
                if item.wheres
                    sql += ' WHERE ' + item.wheres
                # LIMIT condition
                if parseInt(item.limit?) > 0
                    sql += ' LIMIT ' + (parseInt(item.limit)).toString()
                # ORDER BY
                if item.orderby?.field? of fs
                    sql += ' ORDER BY ' + item.orderby.field + (if item.orderby.desc then ' DESC' else '')
                # end
                sql += ';'
                res.sql = sql

            when 'DELETE'
                # base DELETE statement
                sql = 'DELETE FROM `' + table + '`'
                # WHERE condition (required)
                if not item.wheres
                    res.error =
                        code: PARSE_SQL_COMPONENTS_ERROR
                        message: 'missing WHERE conditions for DELETE statement'
                    return res
                else
                    sql += ' WHERE ' + wheres

                res.sql = sql

            # otherwise return error
            else
                res.error =
                    code: PARSE_SQL_COMPONENTS_ERROR
                    message: 'unhandled sql command - `' + command + '`'

        return res


    # General sql insertion wrapper
    _add = (table, items = [], options = {}, callback, fail) ->
        items = [items] if not Array.isArray(items)
        sqls = []
        successes = []
        for item in items
            # preapre sql string and data
            sqlObj = _prepareSql('INSERT', table, item, options)
            if sqlObj.error
                log.e('db _add: failed when building sql object - [' + sqlObj.error + ']', item)
                fail?(sqlObj.error, {command: 'add', data: item})
                return
            # if we need some fields data return for future use
            if options.returns?.length
                sqlObj.success = () ->
                    ret = {}
                    ret[f] = item[f] for f in options.returns
                    successes.push(ret)
            # add sql object to list
            sqls.push(sqlObj)

        # execute sqls
        html5sql.process(sqls, (transaction, results, rowsArray) ->
            log.d('db _add: insert to table `' + table + '` - [' + successes.length + '/' + sqls.length + ']')
            callback?(successes)
        , (error, statement) ->
            log.e('db _add: ' + error.message + ' when processing ' + statement)
            error =
                code: DatabaseError.EXECUTE_SQL_ERROR
                message: error.message
            fail?(error, {command: 'add', data: statement})
        )


    # Single sql statement request. TODO multiple queries in sequence
    _retrieve = (table, query = {}, options = {}, callback, fail) ->
        # get sql object
        sqlObj = _prepareSql('SELECT', table, query, options)
        if sqlObj.error
            log.e('db _retrieve: failed when building sql object - [' + sqlObj.error + ']', item)
            fail?(sqlObj.error, {command: 'retrieve', data: query})
            return
        # execute sql
        html5sql.process([sqlObj], (transaction, results, rowsArray) ->
            log.d('db _retrieve: found ' + rowsArray.length + ' results in `' + table + '`')
            callback?(rowsArray)
        , (error, statement) ->
            log.e('db _retrieve: ' + error.message + ' when processing ' + statement)
            error =
                code: DatabaseError.EXECUTE_SQL_ERROR
                message: error.message
            fail?(error, {command: 'retrieve', data: statement})
        )


    # General deletion wrapper
    _delete = (table, items = [], options = {}, callback, fail) ->
        items = [items] if not Array.isArray(items)
        sqls = []
        successes = []
        for item in items
            # prepare sql object
            sqlObj = _prepareSql('DELETE', table, item, options)
            if sqlObj.error
                log.e('db _delete: failed when building sql object - [' + sqlObj.error + ']')
                fail?(sqlObj.error, {command: 'delete', data: item})
                return
            # add sql object to list
            sqls.push(sqlObj)

        # execute sqls
        html5sql.process(sqls, (transaction, results, rowsArray) ->
            log.d('db _delete: deleted in table `' + table + '` - [' + successes.length + '/' + sqls.length + ']')
            callback?(successes)
        , (error, statement) ->
            log.e('db _delete: ' + error.message + ' when processing ' + statement)
            error =
                code: DatabaseError.EXECUTE_SQL_ERROR
                message: error.message
            fail?(error, {command: 'delete', data: statement})
        )




    # -- Database Public Instance Object --
    self = {}

    # Add bookmarks
    self.addBookmark = (bookmarks = [], callback, fail) ->
        _add('bookmarks', bookmarks, {
            uuids: ['id']
            timestamps: ['created']
            required: ['url']
            returns: ['id', 'url', 'title']
        }, (successes) ->
            log.d('db addBookmark: successfully add ' + successes.length + ' bookmarks, ' + (bookmarks.length - successes.length) + ' failed.')
            callback?(successes)
        , (error, data) ->
            log.e('db addBookmark: ' + error.message)
            fail?(error, data)
        )


    # Add tags
    self.addTag = (tags = [], callback, fail) ->
        _add('tags', tags, {
            uuids: ['id']
            timestamps: ['created']
            required: ['name']
            returns: ['id', 'name']
        }, (successes) ->
            log.d('db addTag: successfully add ' + successes.length + ' tags, ' + (tags.length - successes.length) + ' failed.')
            callback?(successes)
        , (error, data) ->
            log.e('db addTag: ' + error.message)
            fail?(error, data)
        )

    # Add `bookmark ~ tag` link
    self.addLinkBookmarkTag = (links = []) ->
        _add('link-bookmark-tag', links, {
            timestamps: ['created']
            required: ['bookmark_id', 'tag_id']
            returns: ['bookmark_id', 'tag_id']
        }, (successes) ->
            log.d('db addLinkBookmarkTag: successfully add ' + successes.length + ' links, ' + (links.length - successes.length) + ' failed.')
            callback?(successes)
        , (error, data) ->
            log.e('db addTag: ' + error.message)
            fail?(error, data)
        )


    self.retrieveBookmarkById = (id, callback) ->
        _retrieve('bookmarks', {
            fields: ['id','title','url']
            wheres: 'id="' + id + '"'
        }, {}, callback)

    self.retrieveAllBookmarks = (success, failure) ->
        _retrieve('bookmarks', {
            orderby: {field: 'created', desc: true}
        }, {}, (results) ->
            log.d('db retrieveAllBookmarks: found ' + results.length + ' bookmarks.', results)
            success?(results)
        , (e, sql) ->
            log.e('db retrieveAllBookmarks: ' + e.message)
            failure?('db executeSql failed.')
        )


    # dev use, initialize data
    self.initData = () ->
        uuidBookmark = Utils.generateUUID()
        uuidTag = Utils.generateUUID()

        @addBookmark([{
            id: uuidBookmark
            url: 'https://v2ex.com'
            title: 'V2EX'
            favorite: true
        }, {
            url: 'https://inbox.google.com'
            title: 'Google Inbox'
        }, {
            url: 'http://gosugamers.net/dota2'
            title: 'GosuGamers Dota2'
        }])

        @addTag([{name: 'geek'}, {name: 'google'}, {id: uuidTag, name: 'bbs'}, {name: 'game'}])

        @addLinkBookmarkTag([{
            bookmark_id: uuidBookmark
            tag_id: uuidTag
        }])

        @retrieveAllBookmarks()


    # Initialize database
    # TODO now it will drop all tables every time in db_init.sql.
    # will need add reset signal somewhere (by app version?)
    self.init = (options = {}) ->
        xmlhttp = new XMLHttpRequest()
        xmlhttp.onload = () ->
            #log.d('db: load init sql script: ' + xmlhttp.responseText)
            html5sql.process(
                xmlhttp.responseText
                () ->
                    log.d('db: init successfully.')
                    if options.debug
                        self.initData()
                    options.callback?()
                (error, statement) ->
                    log.e('db init: ' + error.message + ' when processing ' + statement)
            )
        xmlhttp.open('GET', 'db_init.sql', true)
        xmlhttp.send()


    return self



