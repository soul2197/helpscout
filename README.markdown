# Helpscout Developers v2 API gem

This gem is in ALPHA.

## Usage

1. You need to create an OAuth2 application before you can use the API: https://developer.helpscout.com/mailbox-api/overview/authentication/ This applies to both Authorization Code flow and Client Credentials flow.

2. Initialize your HelpScout client

```ruby
helpscout = HelpScout::V2::Client.new(HELPSCOUT_APP_ID, HELPSCOUT_APP_SECRET)
```

Note - most of this gem is a WORK IN PROGRESS as there were a number of breaking changes in the v2 API.  You'll have to make changes to the gem to get things working again, but this will give you a starting point.

#### Fetching Users

```ruby
users = helpscout.users
```

#### Fetching Mailboxes

```ruby
mailboxes = helpscout.mailboxes
```

#### Fetching Customers

```ruby
customers = helpscout.customers
```

#### Fetching Conversations

To fetch active conversations:

```ruby
conversations = helpscout.conversations(mailboxId, "active", nil)
```

