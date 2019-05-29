# Help Scout API V2 Client
# http://developer.helpscout.net/
#
# Authentication
# This is an HTTPS-only API. Authentication will be based on OAuth 2.0 using
# the App Credentials (App ID and App Secret), which can be generated in the
# Help Scout UI in User Profile > My Apps. Each set of credentials will map to
# an existing Help Scout user. Results returned from various responses will be
# based upon the role of the user to which the credentials tied.
#
# The client is authenticated by sending a POST to 
# https://api.helpscout.net/v2/oauth2/token with client credentials. A
# successful response will include an access token. Which is used to authorize
# subsequent API request. This access token will expire after 2 hours, after
# which 401 Unauthorized responses will be returned. The client will need to be
# re-authorized at this point
#
# Rate Limiting
# Requests will be limited to 400 requests per minute. Response code 429 will
# be returned when throttle limit has been reached. A "Retry-After" header will
#  be returned indicating how many seconds to wait until retry.
#
# Formats
# Each endpoint will specify the response format in the URL. However, the API
# will only support JSON at this time.
#
# Usage
# 1. Follow the instructions at Help Scout's Developers site to generate 
#    credentials:
#    https://developer.helpscout.com/mailbox-api/overview/authentication
# 2. Add your credentials to config/helpscout.yml:
#    app_id: XXXXXX
#    app_secret: XXXXXX
# 3. Initialize your Help Scout client:
#    HelpScout::Client.new
# 4. You may now query the Help Scout API:
#    mailboxes = HelpScout::Client.mailboxes
#
# You may also initialize a client without using helpscout.yml by passing the
# API Key to new:
# HelpScout::Client.new(app_id: XXXXXX, app_secret: XXXXXX)


require "erb"
require "httparty"
require "yaml"

module HelpScout::V2
  class Client
    include HTTParty

    class TokenExpired < StandardError; end

    # All API requests will be made to: https://api.helpscout.net/. All
    # requests are served over HTTPS. The current version is v2.
    base_uri 'https://api.helpscout.net/v2'
    # authentication_uri 'https://api.helpscout.net/v2/oauth2/token'

    @@settings ||= nil

    # Returns the current Help Scout Client settings.
    # If no settings have been loaded yet, this function will load its
    # configuration from helpscout.yml
    #
    # Settings
    # app_id      String  Help Scout App Id. The API is currently available for
    #                     paying Help Scout accounts (Basic or Standard plan).
    #                     You can generate or find this from your User Profile,
    #                     on the My Apps tab
    # app_secret  String  Help Scout App Secret. This can also be found or
    #                     generated on the My Apps tab
    def self.settings
      if @@settings.nil?
        path = "config/helpscout.yml"
        if File.exist?(path)
          @@settings = YAML.load(ERB.new(File.new(path).read).result)
        end
      end
      @@settings
    end


    # Requests an access_token with the app_id and app_secret from Help Scout
    # Returns access token or raises an error
    def self.request_token(client_id, client_secret)
      path = "/oauth2/token"

      options = {
        body: {
          grant_type: "client_credentials",
          client_id: client_id,
          client_secret: client_secret
        }
      }

      response = Client.post(path, options)
      if response.code >= 400
        raise StandardError,
          "Failed to authenticate client: #{response.parsed_response["error"]}"
      end

      response.parsed_response["access_token"]
    end


    # Requests a single item from the Help Scout API. Should return either an
    # item from the SingleItemEnvelope, or raise an error with an
    # ErrorEnvelope.
    #
    # url     String  A string representing the url for the REST endpoint to be
    #                 queried.
    # params  Hash    A hash of GET parameters to use for this particular
    #                 request.
    #
    # Response
    #           Name    Type   Notes
    #  Header   Status  Int    200
    #  Body     item

    def self.request_item(token, url, params = {})
      item = nil

      request_url = ""
      request_url << url
      if params
        query = ""
        params.each { |k,v| query += "#{k}=#{v}&" }
        request_url << "?" + query
      end

      begin
        response = Client.get(request_url, {headers: { "Authorization" => "Bearer #{token}" }})
      rescue SocketError => se
        raise StandardError, se.message
      end

      if 200 <= response.code && response.code < 300
        envelope = SingleItemEnvelope.new(response)
        if envelope.item
          item = envelope.item
        end
      elsif 401 == response.code
        raise TokenExpired
      elsif 400 <= response.code && response.code < 500
        if response["message"]
          envelope = ErrorEnvelope.new(response)
          raise StandardError, envelope.message
        else
          raise StandardError, response["error"]
        end
      else
        raise StandardError, "Server Response: #{response.code}"
      end

      item
    end


    # Requests a collections of items from the Help Scout API. Should return
    # either an array of items from the CollectionsEnvelope, or raise an error
    # with an ErrorEnvelope.
    #
    # Collections return a maximum of 50 records per page.
    #
    # url     String  A string representing the url for the REST endpoint to be
    #                 queried.
    # params  Hash    A hash of GET parameters to use for this particular
    #                 request.
    #
    # Response
    #           Name    Type   Notes
    #  Header   Status  Int    200
    #  Body     page    Int    Current page that was passed in on the request
    #           pages   Int    Total number of pages available
    #           count   Int    Total number of objects available
    #           items   Array  Collection of objects

    def self.request_items(token, url, params = {})
      items = []

      request_url = ""
      request_url << url
      if params
        query = ""
        params.each { |k,v| query += "#{k}=#{v}&" }
        request_url << "?" + query
      end

      begin
        response = Client.get(request_url, {headers: { "Authorization" => "Bearer #{token}" }})
      rescue SocketError => se
        raise StandardError, se.message
      end

      if 200 <= response.code && response.code < 300
        envelope = CollectionsEnvelope.new(response)
        if envelope.items
          envelope.items.each do |item|
            items << item
          end
        end
      elsif 401 == response.code
        raise TokenExpired
      elsif 400 <= response.code && response.code < 500
        if response["message"]
          envelope = ErrorEnvelope.new(response)
          raise StandardError, envelope.message
        else
          raise StandardError, response["error"]
        end
      else
        raise StandardError, "Server Response: #{response.code}"
      end

      items
    end


    # Requests a collections of items from the Help Scout API. Should return
    # the total count for this collection, or raise an error with an
    # ErrorEnvelope.
    #
    # url     String  A string representing the url for the REST endpoint to be
    #                 queried.
    # params  Hash    A hash of GET parameters to use for this particular
    #                 request.
    #
    # Response
    #           Name    Type   Notes
    #  Header   Status  Int    200
    #  Body     page    Int    Current page that was passed in on the request
    #           pages   Int    Total number of pages available
    #           count   Int    Total number of objects available
    #           items   Array  Collection of objects

    def self.request_count(token, url, params = {})
      request_url = ""
      request_url << url
      if params
        query = ""
        params.each { |k,v| query += "#{k}=#{v}&" }
        request_url << "?" + query
      end

      begin
        response = Client.get(request_url, {headers: { "Authorization" => "Bearer #{token}" }})
      rescue SocketError => se
        raise StandardError, se.message
      end

      if 200 <= response.code && response.code < 300
        envelope = CollectionsEnvelope.new(response)
        envelope.count
      elsif 401 == response.code
        raise TokenExpired
      elsif 400 <= response.code && response.code < 500
        if response["message"]
          envelope = ErrorEnvelope.new(response)
          raise StandardError, envelope.message
        else
          raise StandardError, response["error"]
        end
      else
        raise StandardError, "Server Response: #{response.code}"
      end
    end


    # Sends a POST request to create a single item from the Help Scout API.
    #
    # url     String  A string representing the url to POST.
    # params  Hash    A hash of POST parameters to use for this particular
    #                 request.
    #
    # Response
    #  Name      Type    Notes
    #  Location  String  https://api.helpscout.net/v1/conversations/{id}.json

    def self.create_item(token, url, params = {})
      begin
        response = Client.post(url, {:headers => { 'Content-Type' => 'application/json',  "Authorization" => "Bearer #{token}" }, :body => params })
      rescue SocketError => se
        raise StandardError, se.message
      end

      if response.code == 201
        if response["item"]
          response["item"]
        else
          response["Location"]
        end
      elsif 401 == response.code
        raise TokenExpired
      else
        message = "Server Response: #{response.code} #{response.message}"
        message += " Error: #{response['error']}" if response['error'].present?
        message += " (#{response['validationErrors'].to_json})" if response['validationErrors'].present?
        raise StandardError.new(message)
      end
    end

    # Sends a PUT request to update a single item from the Help Scout API.
    #
    # url     String  A string representing the url to PUT.
    # params  Hash    A hash of PUT parameters to use for this particular
    #                 request.
    #
    # Response
    #  Response  Name    Type     Notes
    #  Header    Status  Integer  200

    def self.update_item(token, url, params = {})
      begin
        response = Client.put(url, { :headers => { 'Content-Type' => 'application/json',  "Authorization" => "Bearer #{token}"}, :body => params })
      rescue SocketError => se
        raise StandardError, se.message
      end

      if response.code == 200
        if response["item"]
          response["item"]
        else
          response["Location"]
        end
      elsif 401 == response.code
        raise TokenExpired
      else
        raise StandardError.new("Server Response: #{response.code} #{response.message}")
      end
    end

    # Sends a POST request to the Help Scout API.
    #
    # url     String  A string representing the url to POST.
    #
    # Response
    #           Name    Type   Notes
    #  Header   Status  Int    200

    def self.post_request(token, url)
      begin
        response = Client.post(url, {headers:  {"Authorization" => "Bearer #{token}"}})
      rescue SocketError => se
        raise StandardError, se.message
      end

      if 200 <= response.code && response.code < 300
        true
      elsif 401 == response.code
        raise TokenExpired
      elsif 400 <= response.code && response.code < 500
        if response["message"]
          envelope = ErrorEnvelope.new(response)
          raise StandardError, envelope.message
        else
          raise StandardError, response["error"]
        end
      else
        raise StandardError, "Server Response: #{response.code}"
      end
    end

  
    # HelpScout::Client.new
    #
    # Initializes the Help Scout Client. Once called, you may use any of the
    # HelpScout::Client methods to query the Help Scout API.
    #
    # key  String  Help Scout API Key. Optional. If not passed, the key will be
    #              loaded from @@settings, which defaults to helpscout.yml.

    def initialize(client_id, client_secret)
      Client.settings

      if client_id.nil? || client_secret.nil?
        client_id = @@settings["client_id"]
        client_secret = @@settings["client_secret"]
      end

      @client_id = client_id
      @client_secret = client_secret

      refresh_token
    end

    def refresh_token
      @token = Client.request_token(@client_id, @client_secret)
    end

    # 
    def with_auth(&block)
      block.call(@token)
    rescue TokenExpired
      refresh_token
      block.call(@token)
    end

    # Get User
    # http://developer.helpscout.net/users/
    #
    # Fetches a single user by id.
    #
    # userId  Int  id of the User being requested
    #
    # Request
    #  REST Method: GET
    #  URL: https://api.helpscout.net/v1/conversations/{conversationId}.json
    #
    #  GET Parameters
    #  Name            Type
    #  conversationId  Int  id of the Conversation being requested
    #
    # Response
    #  Name  Type
    #  item  User

    def user(userId)
      url = "/users/#{userId}.json"
      item = Client.request_item(@auth, url, nil)
      user = nil
      if item
        user = User.new(item)
      end
      user
    end


    # List Users
    # http://developer.helpscout.net/users/
    #
    # Fetches all users
    #
    # Request
    #  REST Method: GET
    #  URL: https://api.helpscout.net/v1/users.json
    #
    #  Parameters:
    #   Name  Type  Required  Default  Notes
    #   page  Int   No        1
    #
    # Response
    #  Name   Type
    #  items  Array  Collection of User objects

    def users
      url = "/users"
      items = with_auth do |token|
        Client.request_items(token, url, :page => 1)
      end
      users = []
      items.each do |item|
        users << User.new(item)
      end
      users
    end


    # List Users by Mailbox
    # http://developer.helpscout.net/users/
    #
    # Fetches all users in a single mailbox
    #
    # mailboxId  Int  id of the Mailbox being requested
    #
    # Request
    #  REST Method: GET
    #  URL: https://api.helpscout.net/v1/mailboxes/{id}/users.json
    #
    #  Parameters:
    #   Name  Type  Required  Default  Notes
    #   page  Int   No        1
    #
    # Response
    #  Name   Type
    #  items  Array  Collection of User objects

    def users_in_mailbox(mailboxId)
      url ="/mailboxes/#{mailboxId}/users.json"
      items = Client.request_items(@auth, url, :page => 1)
      users = []
      items.each do |item|
        users << User.new(item)
      end
      users
    end


    # List Mailboxes
    # http://developer.helpscout.net/mailboxes/
    #
    # Fetches all mailboxes
    #
    # Request
    #  REST Method: GET
    #  URL: https://api.helpscout.net/v1/mailboxes.json
    #
    #  Parameters:
    #   Name  Type  Required  Default  Notes
    #   page  Int   No        1
    #
    # Response
    #  Name   Type
    #  items  Array  Collection of Mailbox objects

    def mailboxes
      url = "/mailboxes.json"
      mailboxes = []
      begin
        items = Client.request_items(@auth, url, {})
        items.each do |item|
          mailboxes << Mailbox.new(item)
        end
      rescue StandardError => e
        puts "List Mailbox Request failed: #{e.message}"
      end
      mailboxes
    end


    # Get Mailbox
    # http://developer.helpscout.net/mailboxes/
    #
    # Fetches a single Mailbox
    #
    # mailboxId  Int  id of the Mailbox being requested
    #
    # Request
    #  REST Method: GET
    #  URL: https://api.helpscout.net/v1/mailboxes/{id}.json
    #
    # Response
    #  Name  Type
    #  item  Mailbox

    def mailbox(mailboxId)
      url = "/mailboxes/#{mailboxId}.json"
      item = Client.request_item(@auth, url, nil)
      mailbox = nil
      if item
        mailbox = Mailbox.new(item)
      end
      mailbox
    end


    # Get Folders
    # http://developer.helpscout.net/mailboxes/
    #
    # Fetches all Folders in a given mailbox
    #
    # mailboxId  Int  id of the Mailbox being requested
    #
    # Request
    #  REST Method: GET
    #  URL: https://api.helpscout.net/v1/mailboxes/{id}/folders.json
    #
    #  Parameters:
    #   Name  Type  Required  Default  Notes
    #   page  Int   No        1
    #
    # Response
    #  Name   Type
    #  items  Array  Collection of Mailbox objects

    def folders_in_mailbox(mailboxId)
      url = "/mailboxes/#{mailboxId}/folders.json"
      items = Client.request_items(@auth, url, :page => 1)
      folders = []
      items.each do |item|
        folders << Folder.new(item)
      end
      folders
    end


    # Get Conversation
    # http://developer.helpscout.net/conversations/get/
    #
    # Fetches a single Conversation
    #
    # conversationId  Int  id of the Conversation being requested
    #
    # Request
    #  REST Method: GET
    #  URL: https://api.helpscout.net/v1/conversations/{id}.json
    #
    # Response
    #  Name  Type
    #  item  Conversation

    def conversation(conversationId)
      url = "/conversations/#{conversationId}.json"

      begin
        item = Client.request_item(@auth, url, nil)
        conversation = nil
        if item
          conversation = Conversation.new(item)
        end
      rescue StandardError => e
        puts "Could not fetch conversation with id #{conversationId}: #{e.message}"
        # raise "Could not fetch conversation with id #{conversationId}: #{e.message}"
      end
    end


    # Create Conversation
    # http://developer.helpscout.net/conversations/create/
    #
    # Creates a new Conversation.
    #
    # Request
    #  REST Method: POST
    #  URL: https://api.helpscout.net/v1/conversations.json
    #
    #  POST Parameters
    #  Name          Type          Required  Notes
    #  conversation  Conversation  Yes
    #  import        boolean       No        The import parameter enables
    #                                        conversations to be created for
    #                                        historical purposes (i.e. if moving
    #                                        from a different platform, you can
    #                                        import your history). When import
    #                                        is set to true, no outgoing emails
    #                                        or notifications will be generated.
    #  reload        boolean       No        Set this parameter to 'true' to
    #                                        return the created conversation in
    #                                        the response.
    #

    def create_conversation(conversation)
      if !conversation
        raise StandardError.new("Missing Conversation")
      end

      url = "/conversations.json"

      begin
        response = Client.create_item(@auth, url, conversation.to_json)
      rescue StandardError => e
        raise StandardError, "Could not create conversation: #{e.message}"
      end
    end

    # Update Conversation
    # http://developer.helpscout.net/help-desk-api/conversations/update/
    #
    # Request
    #  REST Method: PUT
    #  URL: https://api.helpscout.net/v1/conversations/{id}.json
    #  Content-Type: `application/json`
    #
    # Response
    # Response  Name    Type     Notes
    # Header    Status  Integer  200

    def update_conversation(conversation_id, conversation)
      if !conversation
        raise StandardError.new("Missing Conversation")
      end

      url = "/conversations/#{conversation_id}.json"

      begin
        response = Client.update_item(@auth, url, conversation.to_json)
      rescue StandardError => e
        raise StandardError, "Could not update conversation: #{e.message}"
      end
    end

    # List Conversations
    # http://developer.helpscout.net/conversations/list/
    #
    # Fetches conversations in a mailbox with a given status
    #
    # mailboxId      Int       id of the Mailbox being requested
    # status         String    Filter by conversation status
    # limit          Int       This function will page through
    #                          CollectionsEnvelopes until all items are
    #                          returned, unless a limit is specified.
    # modifiedSince  DateTime  Returns conversations that have been modified
    #                          since the given date/time.
    #
    # Possible values for status include:
    # * CONVERSATION_FILTER_STATUS_ALL      (Default)
    # * CONVERSATION_FILTER_STATUS_ACTIVE
    # * CONVERSATION_FILTER_STATUS_PENDING
    #
    # Request
    #  REST Method: GET
    #  URL: https://api.helpscout.net/v1/mailboxes/{mailboxId}/conversations.json
    #
    #  Parameters:
    #   Name           Type      Required  Default  Notes
    #   page           Int       No        1
    #   status         String    No        all      Active/Pending only applies
    #                                               to the following folders:
    #                                               Unassigned
    #                                               My Tickets
    #                                               Drafts
    #                                               Assigned
    #   modifiedSince  DateTime  No                 Returns conversations that
    #                                               have been modified since the
    #                                               given date/time.
    #
    # Response
    #  Name   Type
    #  items  Array  Collection of Conversation objects. Conversation threads
    #                are not returned on this call. To get the conversation
    #                threads, you need to retrieve the full conversation object
    #                via the Get Conversation call.

    CONVERSATION_FILTER_STATUS_ACTIVE = "active"
    CONVERSATION_FILTER_STATUS_ALL = "all"
    CONVERSATION_FILTER_STATUS_PENDING = "pending"

    def conversations(mailboxId, status, limit=0, modifiedSince)
      url = "/mailboxes/#{mailboxId}/conversations.json"

      page = 1
      options = {}

      if limit < 0
        limit = 0
      end

      if status && (status == CONVERSATION_FILTER_STATUS_ACTIVE || status == CONVERSATION_FILTER_STATUS_ALL || status == CONVERSATION_FILTER_STATUS_PENDING)
        options["status"] = status
      end

      if modifiedSince
        options["modifiedSince"] = modifiedSince
      end

      conversations = []

      begin
        options["page"] = page
        items = Client.request_items(@auth, url, options)
        items.each do |item|
          conversations << Conversation.new(item)
        end
        page = page + 1
      rescue StandardError => e
        puts "List Conversations Request failed: #{e.message}"
      end while items && items.count > 0 && (limit == 0 || conversations.count < limit)

      if limit > 0 && conversations.count > limit
        conversations = conversations[0..limit-1]
      end

      conversations
    end


    # List Conversations in Folder
    # http://developer.helpscout.net/conversations/
    #
    # Return conversations in a specific folder of a mailbox.
    #
    # mailboxId      Int       id of the Mailbox being requested
    # folderId       Int       id of the Folder being requested
    # status         String    Filter by conversation status
    # limit          Int       This function will page through
    #                          CollectionsEnvelopes until all items are
    #                          returned, unless a limit is specified.
    # modifiedSince  DateTime  Returns conversations that have been modified
    #                          since the given date/time.
    #
    # Possible values for status include:
    # * CONVERSATION_FILTER_STATUS_ALL      (Default)
    # * CONVERSATION_FILTER_STATUS_ACTIVE
    # * CONVERSATION_FILTER_STATUS_PENDING
    #
    # Request
    #  REST Method: GET
    #  URL: https://api.helpscout.net/v1/mailboxes/{mailboxId}/folders/{folderId}/conversations.json
    #
    #  Parameters:
    #   Name           Type      Required  Default  Notes
    #   page           Int       No        1
    #   status         String    No        all      Active/Pending only applies
    #                                               to the following folders:
    #                                               Unassigned
    #                                               My Tickets
    #                                               Drafts
    #                                               Assigned
    #   modifiedSince  DateTime  No                 Returns conversations that
    #                                               have been modified since the
    #                                               given date/time.
    #
    # Response
    #  Name   Type
    #  items  Array  Collection of Conversation objects. Conversation threads
    #                are not returned on this call. To get the conversation
    #                threads, you need to retrieve the full conversation object
    #                via the Get Conversation call.

    def conversations_in_folder(mailboxId, folderId, status, limit=0, modifiedSince)
      url = "/mailboxes/#{mailboxId}/folders/#{folderId}/conversations.json"

      page = 1
      options = {}

      if limit < 0
        limit = 0
      end

      if status && (status == CONVERSATION_FILTER_STATUS_ACTIVE || status == CONVERSATION_FILTER_STATUS_ALL || status == CONVERSATION_FILTER_STATUS_PENDING)
        options["status"] = status
      end

      if modifiedSince
        options["modifiedSince"] = modifiedSince
      end

      conversations = []

      begin
        options["page"] = page
        items = Client.request_items(@auth, url, options)
        items.each do |item|
          conversations << Conversation.new(item)
        end
        page = page + 1
      rescue StandardError => e
        puts "List Conversations In Folder Request failed: #{e.message}"
      end while items && items.count > 0 && (limit == 0 || conversations.count < limit)

      if limit > 0 && conversations.count > limit
        conversations = conversations[0..limit-1]
      end

      conversations
    end

    # List Conversations by Customer
    # http://developer.helpscout.net/help-desk-api/conversations/list/
    #
    # Fetches conversations in a mailbox with a given customer
    #
    # customerId     Int       id of the customer being requested
    # mailboxId      Int       id of the Mailbox being requested
    # status         String    Filter by conversation status
    # limit          Int       This function will page through
    #                          CollectionsEnvelopes until all items are
    #                          returned, unless a limit is specified.
    # modifiedSince  DateTime  Returns conversations that have been modified
    #                          since the given date/time.
    #
    # Possible values for status include:
    # * CONVERSATION_FILTER_STATUS_ALL      (Default)
    # * CONVERSATION_FILTER_STATUS_ACTIVE
    # * CONVERSATION_FILTER_STATUS_PENDING
    #
    # Request
    #  REST Method: GET
    #  URL: https://api.helpscout.net/v1/mailboxes/{mailboxId}/customers/{customerId}/conversations.json
    #
    #  Parameters:
    #   Name           Type      Required  Default  Notes
    #   page           Int       No        1
    #   status         String    No        all      Active/Pending only applies
    #                                               to the following folders:
    #                                               Unassigned
    #                                               My Tickets
    #                                               Drafts
    #                                               Assigned
    #   modifiedSince  DateTime  No                 Returns conversations that
    #                                               have been modified since the
    #                                               given date/time.
    #
    # Response
    #  Name   Type
    #  items  Array  Collection of Conversation objects. Conversation threads
    #                are not returned on this call. To get the conversation
    #                threads, you need to retrieve the full conversation object
    #                via the Get Conversation call.

    def conversations_with_customer(
      mailboxId,
      customerId,
      status=CONVERSATION_FILTER_STATUS_ALL,
      limit=0,
      modifiedSince=nil
    )
      url = "/mailboxes/#{mailboxId}/customers/#{customerId}/conversations.json"

      page = 1
      options = {}

      if limit < 0
        limit = 0
      end

      if status && (status == CONVERSATION_FILTER_STATUS_ACTIVE || status == CONVERSATION_FILTER_STATUS_ALL || status == CONVERSATION_FILTER_STATUS_PENDING)
        options["status"] = status
      end

      if modifiedSince
        options["modifiedSince"] = modifiedSince
      end

      conversations = []

      begin
        options["page"] = page
        items = Client.request_items(@auth, url, options)
        items.each do |item|
          conversations << Conversation.new(item)
        end
        page = page + 1
      end while items && items.count > 0 && (limit == 0 || conversations.count < limit)

      if limit > 0 && conversations.count > limit
        conversations = conversations[0..limit-1]
      end

      conversations
    end

    # Conversation Count
    # http://developer.helpscout.net/conversations/
    #
    # Returns a count for conversations in a mailbox with a given status
    #
    # mailboxId      Int       id of the Mailbox being requested
    # status         String    Filter by conversation status
    # modifiedSince  DateTime  id of the Mailbox being requested
    #
    # Possible values for status include:
    # * CONVERSATION_FILTER_STATUS_ALL      (Default)
    # * CONVERSATION_FILTER_STATUS_ACTIVE
    # * CONVERSATION_FILTER_STATUS_PENDING
    #
    # Request
    #  REST Method: GET
    #  URL: https://api.helpscout.net/v1/mailboxes/{mailboxId}/conversations.json
    #
    #  Parameters:
    #   Name           Type      Required  Default  Notes
    #   page           Int       No        1
    #   status         String    No        all      Active/Pending only applies
    #                                               to the following folders:
    #                                               Unassigned
    #                                               My Tickets
    #                                               Drafts
    #                                               Assigned
    #   modifiedSince  DateTime  No                 Returns conversations that
    #                                               have been modified since the
    #                                               given date/time.
    #
    # Response
    #  Name   Type
    #  count  Integer  Count of Conversation objects.

    def conversation_count(mailboxId, status, modifiedSince)
      url = "/mailboxes/#{mailboxId}/conversations.json"

      page = 1
      options = {}

      if status && (status == CONVERSATION_FILTER_STATUS_ACTIVE || status == CONVERSATION_FILTER_STATUS_ALL || status == CONVERSATION_FILTER_STATUS_PENDING)
        options["status"] = status
      end

      if modifiedSince
        options["modifiedSince"] = modifiedSince
      end

      conversations = []

      begin
        options["page"] = page
        count = Client.request_count(@auth, url, options)
      rescue StandardError => e
        puts "Conversation Count Request failed: #{e.message}"
      end
    end


    # Get Attachment Data
    # http://developer.helpscout.net/conversations/
    #
    # Fetches the AttachmentData from a given Attachment
    #
    # attachmentId  Int  id of the Attachment being requested
    #
    # Request
    #  REST Method: GET
    #  URL: https://api.helpscout.net/v1/attachments/{id}/data.json
    #
    # Response
    #  Name  Type
    #  item  Conversation::AttachmentData

    def attachment_data(attachmentId)
      url = "/attachments/#{attachmentId}/data.json"
      item = Client.request_item(@auth, url, nil)
      attachmentData = nil
      if item
        attachmentData = Conversation::AttachmentData.new(item)
      end

      attachmentData
    end


    # Get Customer
    # http://developer.helpscout.net/customers/
    #
    # Fetches a single Customer
    #
    # customerId  Int  id of the Customer being requested
    #
    # Request
    #  REST Method: GET
    #  URL: https://api.helpscout.net/v1/customers/{id}.json
    #
    # Response
    #  Name  Type
    #  item  Customer

    def customer(customerId)
      url = "/customers/#{customerId}.json"
      item = Client.request_item(@auth, url, nil)
      customer = nil
      if item
        customer = Customer.new(item)
      end

      customer
    end


    # List Customers
    # http://developer.helpscout.net/customers/
    #
    # Customers can be filtered on any combination of first name, last name, and
    # email.
    #
    # Customers are returned by createdAt date, from newest to oldest.
    #
    # Request
    #  REST Method: GET
    #  URL: https://api.helpscout.net/v1/customers.json
    #
    #  Parameters:
    #   Name           Type      Required  Default  Notes
    #   Name       Type    Required  Default
    #   firstName  String  No
    #   lastName   String  No
    #   email      String  No
    #   page       Int     No        1
    #
    # Response
    #  Name   Type
    #  items  Array  Collection of Customer objects.

    def customers(limit=0, firstName=nil, lastName=nil, email=nil)
      url = "/customers.json"

      page = 1
      options = {}

      if limit < 0
        limit = 0
      end

      if firstName
        options["firstName"] = firstName
      end

      if lastName
        options["lastName"] = lastName
      end

      if email
        options["email"] = email
      end

      customers = []

      begin
        options["page"] = page
        items = Client.request_items(@auth, url, options)
        items.each do |item|
          customers << Customer.new(item)
        end
        page = page + 1
      rescue StandardError => e
        puts "Request failed: #{e.message}"
      end while items && items.count > 0 && (limit == 0 || customers.count < limit)

      if limit > 0 && customers.count > limit
        customers = customers[0..limit-1]
      end

      customers
    end

    # Helper method to find customers by email
    def customers_by_email(email)
      customers(0, nil, nil, email)
    end

    # Create Customer
    # http://developer.helpscout.net/customers/create/
    #
    # Creates a new Customer.
    #
    # Request
    #  REST Method: POST
    #  URL: https://api.helpscout.net/v1/customers.json
    #
    #  POST Parameters
    #  Name      Type      Required  Notes
    #  customer  Customer  Yes       The body of the request
    #  reload    boolean   No        Set to true to return the customer in the
    #                                response.
    # Response
    #  Response   Name      Type    Notes
    #  Header     Status    Integer 201
    #  Header     Location  String  https://api.helpscout.net/v1/customer/{id}.json

    def create_customer(customer)
      if !customer
        raise StandardError.new("Missing Customer")
      end

      url = "/customers.json"

      begin
        item = Client.create_item(@auth, url, customer.to_json)
        Customer.new(item)
      rescue StandardError => e
        puts "Could not create customer: #{e.message}"
        false
      end
    end

    # Run Workflow on Conversation
    # http://developer.helpscout.net/help-desk-api/workflows/conversation/
    #
    # Run Workflow on a Single Conversation.
    #  Applies the actions for the specified manual workflow on the specified
    #  conversation. Specifying an automatic workflow will return an error.
    #
    # Request
    #  REST Method: POST
    #  URL: https://api.helpscout.net/v1/workflows/{id}/conversations/{conversation-id}.json
    #
    # Response
    #  Response   Name      Type     Notes
    #  Header     Status    Integer  200

    def run_workflow(workflow_id, conversation_id)
      url = "/workflows/#{ workflow_id }/conversations/#{ conversation_id }.json"

      begin
        response = Client.post_request(@auth, url)
      rescue StandardError => e
        puts "Could not run workflow (workflow_id: #{workflow_id.inspect}) on conversation_id: #{ conversation_id.inspect}\n#{ e }"
      end
    end

    # Create Conversation Thread
    # http://developer.helpscout.net/help-desk-api/conversations/create-thread/
    #
    # Request
    #  REST Method: POST
    #  URL: https://api.helpscout.net/v1/conversations/{id}.json
    #  Content-Type: `application/json`
    #
    # Parameters:
    #  Name       Type                  Required     Default      Notes
    #  thread     ConversationThread    Yes                       The body of the request.
    #  imported   boolean               No           false        When the 'imported' request parameter
    #                                                               is set to true, no outgoing emails
    #                                                               or notifications will be generated.
    #  reload     boolean               No           false        Set this request parameter to true to
    #                                                               return the entire conversation in
    #                                                               the response.
    #
    # Response
    #  Response   Name      Type     Notes
    #  Header     Status    Integer  201

    def create_conversation_thread(conversation_id, conversation_thread)
      if !conversation_id
        raise StandardError.new("Missing `conversation_id`")
      end

      if !conversation_thread
        raise StandardError.new("Missing ConversationThread")
      end

      url = "/conversations/#{conversation_id}.json"

      begin
        response = Client.create_item(@auth, url, conversation_thread.to_json)
      rescue StandardError => e
        raise StandardError, "Could not create conversation thread: #{e.message}"
      end
    end

    # Create Attachment
    # http://developer.helpscout.net/conversations/create-attachment/
    #
    # Creates a new Attachment.
    #
    # Request
    #  REST Method: POST
    #  URL: https://api.helpscout.net/v1/attachments.json
    #
    #  POST Parameters
    #  Name          Type          Required  Notes
    #  attachment    Attachment    Yes
    #

    def create_attachment(attachment)
      if !attachment
        raise StandardError.new("Missing Attachment")
      end

      url = "/attachments.json"

      begin
        response = Client.create_item(@auth, url, attachment.to_json)
      rescue StandardError => e
        puts "Could not create attachment: #{e.message}"
      end
    end
  end
end
