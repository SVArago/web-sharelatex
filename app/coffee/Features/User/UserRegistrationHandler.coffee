sanitize = require('sanitizer')
User = require("../../models/User").User
UserCreator = require("./UserCreator")
AuthenticationManager = require("../Authentication/AuthenticationManager")
NewsLetterManager = require("../Newsletter/NewsletterManager")
async = require("async")
logger = require("logger-sharelatex")
request = require("request")

module.exports =
	validateEmail : (email) ->
		re = /^(([^<>()[\]\\.,;:\s@\"]+(\.[^<>()[\]\\.,;:\s@\"]+)*)|(\ ".+\"))@((\[[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\])|(([a-zA -Z\-0-9]+\.)+[a-zA-Z]{2,}))$/
		return re.test(email)

	hasZeroLengths : (props) ->
		hasZeroLength = false
		props.forEach (prop) ->
			if prop.length == 0
				hasZeroLength = true
		return hasZeroLength

	_registrationRequestIsValid : (body, callback)->
		email = sanitize.escape(body.email).trim().toLowerCase()
		password = body.password
		username = email.match(/^[^@]*/)
		if @hasZeroLengths([password, email])
			return false
		else if !@validateEmail(email)
			return false
		else
			return true

	_createNewUserIfRequired: (user, userDetails, callback)->
		if !user?
			UserCreator.createNewUser {holdingAccount:false, email:userDetails.email}, callback
		else
			callback null, user

	registerNewUser: (userDetails, isAdmin, callback)->
		self = @
		requestIsValid = @_registrationRequestIsValid userDetails
		if !requestIsValid
			return callback(new Error("request is not valid"))
		userDetails.email = userDetails.email?.trim()?.toLowerCase()
		User.findOne email:userDetails.email, (err, user)->
			if err?
				return callback err
			if user?.holdingAccount == false
				return callback(new Error("EmailAlreadyRegistered"), user)

			doCreateUser = () ->
				self._createNewUserIfRequired user, userDetails, (err, user)->
					if err?
						return callback(err)
					async.series [
						(cb)-> User.update {_id: user._id}, {"$set":{holdingAccount:false}}, cb
						(cb)-> AuthenticationManager.setUserPassword user._id, userDetails.password, cb
						(cb)->
							NewsLetterManager.subscribe user, ->
							cb() #this can be slow, just fire it off
					], (err)->
						logger.log user: user, "registered"
						callback(err, user)

			if isAdmin
				doCreateUser()
			else
				opts =
					method: "post"
					uri: "https://www.arago.utwente.nl/api/is_mail_known.php"
					json: true
					body:
						email: userDetails.email
				request opts, (err, response, body) ->
					if err?
						return callback(err)
					if not body.known
						return callback(new Error("RegistrationDenied"), null)
						doCreateUser()



