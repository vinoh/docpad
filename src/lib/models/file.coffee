# Import
pathUtil = require('path')
balUtil = require('bal-util')
typeChecker = require('typechecker')
{TaskGroup} = require('taskgroup')
safefs = require('safefs')
mime = require('mime')
extendr = require('extendr')
{extractOptsAndCallback} = require('extract-opts')

# Import: Optional
jschardet = null
Iconv = null

# Local
{Backbone,Model} = require('../base')
docpadUtil = require('../util')


# ---------------------------------
# File Model

class FileModel extends Model

	# ---------------------------------
	# Properties

	# Model Class
	klass: FileModel

	# Model Type
	type: 'file'

	# The out directory path to put the file
	outDirPath: null

	# Whether or not we should detect encoding
	detectEncoding: false

	# Stat Object
	stat: null

	# File data
	# When we do not have a path to scan
	# we can just pass over some data instead
	data: null

	# File buffer
	buffer: null

	# The parsed file meta data (header)
	# Is a Backbone.Model instance
	meta: null

	# Get Opts
	getOpts: ->
		return {@outDirPath, @detectEncoding, @stat, @data, @buffer, @meta}

	# Clone
	clone: ->
		opts = @getOpts()
		attrs = @getAttributes()
		instance = new @klass(attrs, opts)
		instance._events = extendr.deepExtend(@_events)
		return instance


	# ---------------------------------
	# Attributes

	defaults:

		# ---------------------------------
		# Automaticly set variables

		# The unique document identifier
		id: null

		# The file's name without the extension
		basename: null

		# The out file's name without the extension
		outBasename: null

		# The file's last extension
		# "hello.md.eco" -> "eco"
		extension: null

		# The extension used for our output file
		outExtension: null

		# The file's extensions as an array
		# "hello.md.eco" -> ["md","eco"]
		extensions: null  # Array

		# The file's name with the extension
		filename: null

		# The full path of our source file, only necessary if called by @load
		fullPath: null

		# The full directory path of our source file
		fullDirPath: null

		# The output path of our file
		outPath: null

		# The output path of our file's directory
		outDirPath: null

		# The file's name with the rendered extension
		outFilename: null

		# The relative path of our source file (with extensions)
		relativePath: null

		# The relative output path of our file
		relativeOutPath: null

		# The relative directory path of our source file
		relativeDirPath: null

		# The relative output path of our file's directory
		relativeOutDirPath: null

		# The relative base of our source file (no extension)
		relativeBase: null

		# The relative base of our out file (no extension)
		releativeOutBase: null

		# The MIME content-type for the source file
		contentType: null

		# The MIME content-type for the out file
		outContentType: null

		# The date object for when this document was created
		ctime: null

		# The date object for when this document was last modified
		mtime: null

		# Does the file actually exist on the file system
		exists: null


		# ---------------------------------
		# Content variables

		# The encoding of the file
		encoding: null

		# The raw contents of the file, stored as a String
		source: null

		# The contents of the file, stored as a String
		content: null


		# ---------------------------------
		# User set variables

		# The title for this document
		# Useful for page headings
		title: null

		# The name for this document, defaults to the outFilename
		# Useful for navigation listings
		name: null

		# The date object for this document, defaults to mtime
		date: null

		# The generated slug (url safe seo title) for this document
		slug: null

		# The url for this document
		url: null

		# Alternative urls for this document
		urls: null  # Array

		# Whether or not we ignore this document (do not render it)
		ignored: false

		# Whether or not we should treat this file as standalone (that nothing depends on it)
		standalone: false



	# ---------------------------------
	# Helpers

	# Set Data
	setData: (data) ->
		@data = data
		@

	# Get Data
	getData: ->
		return @data

	# Set Buffer
	setBuffer: (buffer) ->
		@buffer = buffer
		@

	# Get Buffer
	getBuffer: ->
		return @buffer

	# Set Stat
	setStat: (stat) ->
		@stat = stat
		@set(
			ctime: new Date(stat.ctime)
			mtime: new Date(stat.mtime)
		)
		@

	# Get Stat
	getStat: ->
		return @stat

	# Get Attributes
	getAttributes: ->
		attrs = @toJSON()
		attrs = extendr.dereference(attrs)
		return attrs

	# To JSON
	toJSON: ->
		data = super
		data.meta = @getMeta().toJSON()
		return data

	# Get Meta
	getMeta: (args...) ->
		@meta = new Model()  if @meta is null
		if args.length
			return @meta.get(args...)
		else
			return @meta

	# Set Meta
	setMeta: (attrs) ->
		attrs = attrs.toJSON?() ? attrs
		@getMeta().set(attrs)
		@set(attrs)
		return @

	# Set Meta Defaults
	setMetaDefaults: (defaults) ->
		@getMeta().setDefaults(defaults)
		@setDefaults(defaults)
		return @

	# Get Filename
	getFilename: ({filename,fullPath,relativePath}) ->
		filename or= @get('filename')
		if !filename
			filePath = @get('fullPath') or @get('relativePath')
			if filePath
				filename = pathUtil.basename(filePath)
		return filename or null

	# Get Extensions
	getExtensions: ({extensions,filename}) ->
		extensions or= @get('extensions') or null
		if (extensions or []).length is 0
			filename = @getFilename({filename})
			if filename
				extensions = docpadUtil.getExtensions(filename)
		return extensions or null

	# Get Content
	getContent: ->
		return @get('content') or @getBuffer()

	# Get Out Content
	getOutContent: ->
		return @getContent()

	# Is Text?
	isText: ->
		return @get('encoding') isnt 'binary'

	# Is Binary?
	isBinary: ->
		return @get('encoding') is 'binary'

	# Set the url for the file
	setUrl: (url) ->
		@addUrl(url)
		@set({url})
		@

	# Add a url
	# Allows our file to support multiple urls
	addUrl: (url) ->
		# Multiple Urls
		if url instanceof Array
			for newUrl in url
				@addUrl(newUrl)

		# Single Url
		else if url
			found = false
			urls = @get('urls')
			for existingUrl in urls
				if existingUrl is url
					found = true
					break
			urls.push(url)  if not found
			@trigger('change:urls', @, urls, {})
			@trigger('change', @, {})

		# Chain
		@

	# Remove a url
	# Removes a url from our file
	removeUrl: (userUrl) ->
		urls = @get('urls')
		for url,index in urls
			if url is userUrl
				urls.splice(index,1)
				break
		@

	# Get a Path
	# If the path starts with `.` then we get the path in relation to the document that is calling it
	# Otherwise we just return it as normal
	getPath: (relativePath, parentPath) ->
		if /^\./.test(relativePath)
			relativeDirPath = @get('relativeDirPath')
			path = pathUtil.join(relativeDirPath, relativePath)
		else
			if parentPath
				path = pathUtil.join(parentPath, relativePath)
			else
				path = relativePath
		return path


	# ---------------------------------
	# Actions

	# Initialize
	initialize: (attrs,opts={}) ->
		# Prepare
		{outDirPath, detectEncoding, stat, data, buffer, meta} = opts

		# Special
		@detectEncoding = detectEncoding  if detectEncoding?
		@outDirPath     = outDirPath      if outDirPath

		# Defaults
		defaults =
			extensions: []
			urls: []
			id: @cid

		# Stat
		if stat
			@setStat(stat)
		else
			defaults.ctime = new Date()
			defaults.mtime = new Date()

		# Defaults
		@set(defaults)

		# Data
		if attrs.data?
			data = attrs.data
			delete attrs.data
			delete @attributes.data
		if data?
			@setData(data)

		# Buffer
		if attrs.buffer?
			buffer = attrs.buffer
			delete attrs.buffer
			delete @attributes.buffer
		if buffer?
			@setBuffer(buffer)

		# Meta
		if attrs.meta?
			@setMeta(attrs.meta)
			delete attrs.meta
		if meta
			@setMeta(meta)

		# Super
		super

	# Load
	# If the fullPath exists, load the file
	# If it doesn't, then parse and normalize the file
	load: (opts={},next) ->
		# Prepare
		[opts,next] = extractOptsAndCallback(opts,next)
		file = @
		exists = opts.exists ? false

		# Fetch
		fullPath = @get('fullPath')
		filePath = fullPath or @get('relativePath') or @get('filename')

		# Log
		file.log('debug', "Loading the file: #{filePath}")

		# Async
		tasks = new TaskGroup().setConfig(concurrency:0).once 'complete', (err) =>
			return next(err)  if err
			file.log('debug', "Loaded the file: #{filePath}")
			file.parse (err) ->
				return next(err)  if err
				file.normalize (err) ->
					return next(err)  if err
					return next(null, file.buffer)

		# If data is set, use that as the buffer
		data = file.getData()
		if data?
			buffer = new Buffer(data)
			file.setBuffer(buffer)

		# If stat is set, use that
		if opts.stat
			file.setStat(opts.stat)

		# If buffer is set, use that
		if opts.buffer
			file.setBuffer(opts.buffer)

		# Stat the file and cache the result
		tasks.addTask (complete) ->
			# Otherwise fetch new stat
			if fullPath and exists and opts.stat? is false
				return safefs.stat fullPath, (err,fileStat) ->
					return complete(err)  if err
					file.setStat(fileStat)
					return complete()
			else
				return complete()

		# Read the file and cache the result
		tasks.addTask (complete) ->
			# Otherwise fetch new buffer
			if fullPath and exists and opts.buffer? is false
				return safefs.readFile fullPath, (err,buffer) ->
					return complete(err)  if err
					file.setBuffer(buffer)
					return complete()
			else
				return complete()

		# Run the tasks
		if fullPath
			safefs.exists fullPath, (_exists) ->
				exists = _exists
				file.set({exists})
				tasks.run()
		else
			tasks.run()

		# Chain
		@

	# Parse
	# Parse our buffer and extract meaningful data from it
	# next(err)
	parse: (opts={},next) ->
		# Prepare
		[opts,next] = extractOptsAndCallback(opts,next)
		buffer = @getBuffer()
		fullPath = @get('fullPath')
		encoding = @get('encoding') or null
		changes = {}

		# Detect Encoding
		if encoding? is false or opts.reencode is true
			isText = balUtil.isTextSync(fullPath,buffer)

			# Text
			if isText is true
				# Detect source encoding if not manually specified
				if @detectEncoding
					# Import
					jschardet ?= require('jschardet')
					try
						Iconv ?= require('iconv').Iconv
					catch err
						Iconv = null

					# Detect
					encoding ?= jschardet.detect(buffer)?.encoding or 'utf8'
				else
					encoding ?= 'utf8'

				# Convert into utf8
				unless encoding.toLowerCase() in ['ascii','utf8','utf-8']
					if Iconv?
						@log('info', "Converting encoding #{encoding} to UTF-8 on #{fullPath}")
						try
							buffer = new Iconv(encoding,'utf8').convert(buffer)
						catch err
							@log('warn', "Encoding conversion failed, therefore we cannot convert the encoding #{encoding} to UTF-8 on #{fullPath}")
					else
						@log('warn', "Iconv did not load, therefore we cannot convert the encoding #{encoding} to UTF-8 on #{fullPath}")

				# Apply
				changes.encoding = encoding

			# Binary
			else
				# Set
				encoding = 'binary'

				# Apply
				changes.encoding = encoding

		# Binary
		if encoding is 'binary'
			# Set
			content = source = ''

			# Apply
			changes.content = content
			changes.source = source

		# Text
		else
			# Set
			source = buffer.toString('utf8')
			content = source

			# Apply
			changes.content = content
			changes.source = source

		# Apply
		@set(changes)

		# Next
		next()
		@

	# Normalize data
	# Normalize any parsing we have done, as if a value has updates it may have consequences on another value. This will ensure everything is okay.
	# next(err)
	normalize: (opts={},next) ->
		# Prepare
		[opts,next] = extractOptsAndCallback(opts,next)
		changes = {}
		meta = @getMeta()

		# App specified
		filename = opts.filename or @get('filename') or null
		relativePath = opts.relativePath or @get('relativePath') or null
		fullPath = opts.fullPath or @get('fullPath') or null
		mtime = opts.mtime or @get('mtime') or null

		# User specified
		date = opts.date or meta.get('date') or null
		name = opts.name or meta.get('name') or null
		slug = opts.slug or meta.get('slug') or null
		url = opts.url or meta.get('url') or null
		contentType = opts.contentType or meta.get('contentType') or null
		outContentType = opts.outContentType or meta.get('outContentType') or null
		outFilename = opts.outFilename or meta.get('outFilename') or null
		outExtension = opts.outExtension or meta.get('outExtension') or null
		outPath = opts.outPath or meta.get('outPath') or null

		# Force specifeid
		extensions = null
		extension = null
		basename = null
		outBasename = null
		relativeOutPath = null
		relativeDirPath = null
		relativeOutDirPath = null
		relativeBase = null
		relativeOutBase = null
		outDirPath = null
		fullDirPath = null

		# filename
		changes.filename = filename = @getFilename({filename, relativePath, fullPath})

		# check
		if !filename
			err = new Error('filename is required, it can be specified via filename, fullPath, or relativePath')
			return next(err)

		# relativePath
		if !relativePath and filename
			changes.relativePath = relativePath = filename

		# force basename
		changes.basename = basename = docpadUtil.getBasename(filename)

		# force extensions
		changes.extensions = extensions = @getExtensions({filename})

		# force extension
		changes.extension = extension = docpadUtil.getExtension(extensions)

		# force fullDirPath
		if fullPath
			changes.fullDirPath = fullDirPath = docpadUtil.getDirPath(fullPath)

		# force relativeDirPath
		changes.relativeDirPath = relativeDirPath = docpadUtil.getDirPath(relativePath)

		# force relativeBase
		changes.relativeBase = relativeBase =
			if relativeDirPath
				pathUtil.join(relativeDirPath, basename)
			else
				basename

		# force contentType
		if !contentType
			changes.contentType = contentType = mime.lookup(fullPath or relativePath)

		# force date
		if !date
			changes.date = date = mtime or @get('date') or new Date()

		# force outFilename
		if !outFilename and !outPath
			changes.outFilename = outFilename = docpadUtil.getOutFilename(basename, outExtension or extensions.join('.'))

		# force outPath
		if !outPath
			changes.outPath = outPath = pathUtil.resolve(@outDirPath, relativeDirPath, outFilename)

		# force outDirPath
		changes.outDirPath = outDirPath = docpadUtil.getDirPath(outPath)

		# force outFilename
		changes.outFilename = outFilename = docpadUtil.getFilename(outPath)

		# force outBasename
		changes.outBasename = outBasename = docpadUtil.getBasename(outFilename)

		# force outExtension
		changes.outExtension = outExtension = docpadUtil.getExtension(outFilename)

		# force relativeOutPath
		changes.relativeOutPath = relativeOutPath = outPath.replace(@outDirPath, '').replace(/^[\/\\]/, '')

		# force relativeOutDirPath
		changes.relativeOutDirPath = relativeOutDirPath = docpadUtil.getDirPath(relativeOutPath)

		# force relativeOutBase
		changes.relativeOutBase = relativeOutBase = pathUtil.join(relativeOutDirPath, outBasename)

		# force name
		if !name
			changes.name = name = outFilename

		# force url
		_defaultUrl = docpadUtil.getUrl(relativeOutPath)
		if url
			@setUrl(url)
			@addUrl(_defaultUrl)
		else
			@setUrl(_defaultUrl)

		# force outContentType
		if !outContentType and contentType
			changes.outContentType = outContentType = mime.lookup(outPath or relativeOutPath) or contentType

		# force slug
		if !slug
			changes.slug = slug = docpadUtil.getSlug(relativeOutBase)

		# Apply
		@set(changes)

		# Next
		next()
		@

	# Contextualize data
	# Put our data into perspective of the bigger picture. For instance, generate the url for it's rendered equivalant.
	# next(err)
	contextualize: (opts={},next) ->
		# Prepare
		[opts,next] = extractOptsAndCallback(opts,next)

		# Forward
		next()
		@


	# ---------------------------------
	# CRUD

	# Write the rendered file
	# next(err)
	write: (opts,next) ->
		# Prepare
		[opts,next] = extractOptsAndCallback(opts,next)
		file = @

		# Fetch
		opts.path      or= @get('outPath')
		opts.encoding  or= @get('encoding')
		opts.content   or= @getContent()
		opts.type      or= 'file'

		# Check
		# Sometimes the out path could not be set if we are early on in the process
		unless opts.path
			next()
			return @

		# Convert utf8 to original encoding
		unless opts.encoding.toLowerCase() in ['ascii','utf8','utf-8','binary']
			if Iconv?
				@log('info', "Converting encoding UTF-8 to #{opts.encoding} on #{opts.path}")
				try
					opts.content = new Iconv('utf8',opts.encoding).convert(opts.content)
				catch err
					@log('warn', "Encoding conversion failed, therefore we cannot convert the encoding UTF-8 to #{opts.encoding} on #{opts.path}")
			else
				@log('warn', "Iconv did not load, therefore we cannot convert the encoding UTF-8 to #{opts.encoding} on #{opts.path}")

		# Log
		file.log 'debug', "Writing the #{opts.type}: #{opts.path} #{opts.encoding}"

		# Write data
		safefs.writeFile opts.path, opts.content, (err) ->
			# Check
			return next(err)  if err

			# Log
			file.log 'debug', "Wrote the #{opts.type}: #{opts.path} #{opts.encoding}"

			# Next
			next()

		# Chain
		@

	# Delete the file
	# next(err)
	delete: (next) ->
		# Prepare
		file = @
		fileOutPath = @get('outPath')

		# Check
		# Sometimes the out path could not be set if we are early on in the process
		unless fileOutPath
			next()
			return @

		# Log
		file.log 'debug', "Delete the file: #{fileOutPath}"

		# Check existance
		safefs.exists fileOutPath, (exists) ->
			# Exit if it doesn't exist
			return next()  unless exists
			# If it does exist delete it
			safefs.unlink fileOutPath, (err) ->
				# Check
				return next(err)  if err

				# Log
				file.log 'debug', "Deleted the file: #{fileOutPath}"

				# Next
				next()

		# Chain
		@

# Export
module.exports = FileModel
