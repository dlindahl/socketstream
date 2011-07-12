# Users
# -----
# Manages users online within the cluster and connected to this particular instance
# TODO: Handle errors by processing callbacks

util = require('util')

key = SS.config.redis.key_prefix


# Users Connected (to this server instance)
_connected = {}
exports.connected =

  add: (uid, socket) ->
    if _connected[uid]
      _connected[uid].push(socket) unless _connected[uid].contains(socket)
    else
      _connected[uid] = [socket]

  remove: (uid) ->
    delete _connected[uid]
    
  getAll: (uid) ->
    a = _connected[uid]
    if a and a.any() then a else []


# Users Online
exports.online =

  # Get a (potentially huge) list of all User IDs online right now
  now: (cb = console.log) ->
    R.smembers "#{key}:online:now", (err, data) -> cb(data)

  # Add a User ID to the list of Users Online
  add: (uid) ->
    R.sadd "#{key}:online:now", uid
    @confirm(uid)
  
  # Confirm a User ID is still online
  confirm: (uid) ->
    R.sadd "#{key}:online:at:#{minuteCode()}", uid
  
  # Remove a User ID from the list of Users Online
  remove: (uid) ->
    R.srem "#{key}:online:now", uid
    
  # Purges any users which haven't 'confirmed' themselves online within SS.config.users.online.mins_until_offline (default = 2)
  # Each minute gets it's own key in Redis. Every SS.config.users.online.update_interval (default = 60 seconds) we run 
  # SS.users.online.update() to union all the users who've confirmed within the last SS.config.users.online.mins_until_offline (default = 2)
  # and remove everyone else. As Redis evolves we should be able to find more efficient ways to do this.
  update: ->
    SS.log.users.online.update.start()
    
    # Concat all the User IDs which have been online within the last X minutes in a temporary key "ss:online:recent"
    keys = [0..(SS.config.users.online.mins_until_offline - 1)].map (mins_ago) -> "#{key}:online:at:#{minuteCode(mins_ago)}"
    args = ["#{key}:online:recent"].concat(keys)
    R.sunionstore.apply(R, args)
    
    # Compares the people online now to those in the last X mins, effectively removing anyone who went offline X mins ago
    R.sinterstore "#{key}:online:now", "#{key}:online:now", "#{key}:online:recent"
    
    # Run this again in SS.config.users.online.update_secs seconds (default = 60)
    setTimeout arguments.callee, (SS.config.users.online.update_interval * 1000)
    
    # Delete old timestamp keys we no longer need (unless we choose to keep them for analytical purposes)
    unless SS.config.users.online.keep_historic
      keys = [0..(SS.config.users.online.mins_until_offline)].map (mins_ago) -> "#{key}:online:at:#{minuteCode(mins_ago)}"
      R.del.apply(R, keys)
      
    SS.log.users.online.update.complete()


# Private Helpers

minuteCode = (mins_ago = 0) ->
  t = Math.ceil(Number(new Date() / 1000))
  t -= (t % 60)
  t -= (mins_ago * 60)
