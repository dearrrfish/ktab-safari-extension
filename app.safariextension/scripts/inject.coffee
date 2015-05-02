
#handleMessage = (event) ->
    #if (event.name is 'linkClicked')
        #lastLinkClickedUrl = event.message.url
        #lastLinkClickedTime = event.message.clickTime

#safari.self.addEventListener('message', handleMessage, false)
