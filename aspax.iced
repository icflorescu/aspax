fs   = require 'fs'
util = require 'util'
path = require 'path'

yml    = require 'js-yaml'
clc    = require 'cli-color'
gaze   = require 'gaze'
ft     = require 'fs-tools'
uglify = require 'uglify-js'
csso   = require 'csso'

CONFIG_FILE_BASENAME = 'aspax.yml'
EOL                  = require('os').EOL

SPECS_SPLIT_REGEX = ///
  \s*  # optional white-space chars
  \|   # vertical line
  \s*  # optional white-space chars
///

CSS_URL_REGEX = ///
  url\(              # url(
    ['"]?            # optional single or double-quote
    ([^'"\)\?\#]+)   # capture -> one or more chars except single-quote, double-quote, right-bracket, question-mark or number-sign
    ([^'"\)]*)       # capture -> any chars except single-quote, double-quote, right-bracket
    ['"]?            # optional single or double-quote
  \)                 # )
///gi

class AspaX

  constructor: (@src, @dst, @pfx, @out) ->
    # We won't have @src in case we're just cleaning stuff...
    @configFile = path.resolve @src, CONFIG_FILE_BASENAME if @src

  # Build config object, depending on mode (dev|prod) and asset flags
  _buildConfig: (mode, callback) ->
    timestamp = (new Date).getTime()

    await fs.readFile @configFile, 'utf8', defer err, contents
    return callback err if err

    try
      contents = yml.load contents
    catch err
      return callback err

    @config = {}
    for own asset, src of contents
      parts       = asset.split SPECS_SPLIT_REGEX
      name        = parts[0]
      flags       = parts[1..]
      ext         = path.extname(name).toLowerCase()

      action      = if ext in ['.js', '.css'] then 'build' else 'copy'
      min         = mode is 'prod' and 'min' in flags

      sources = []
      for source in (if util.isArray src then src else [src])
        parts = source.split SPECS_SPLIT_REGEX
        sources.push { file: parts[0], flags: parts[1..] }

      destination = path.join path.dirname(name), path.basename(name, ext)
      destination += "-#{timestamp}" if mode is 'prod' and 'fp' in flags
      destination += '.min'          if min
      destination += ext

      @config[name] = { action, min, sources, destination }

    callback()

  # Build triggers for each asset, depending on its source components / imports
  _buildTriggers: (asset, config, callback) ->
    config.triggers = []
    errors = {}
    await
      for source in config.sources
        sourceFile     = source.file
        sourceFullPath = path.resolve @src, sourceFile
        config.triggers.push sourceFullPath
        ext = path.extname(sourceFile).toLowerCase()
        if @config[asset].action is 'build' and ext not in ['.js', '.css']
          try
            plugin = require path.resolve 'node_modules', "aspax-#{ext[1..]}-handler"
            if typeof plugin.findImports is 'function'
              plugin.findImports config.triggers, sourceFullPath, defer errors[sourceFile]
    for own sourceFile, err of errors when err
      console.log clc.red "error while trying to look for additional watch triggers in #{sourceFile}: ", err
    callback()

  # Generate a source header comment
  _getSourceHeader: (sourceFile) ->
    output = "/* -- #{sourceFile} "
    output += '-' for i in [sourceFile.length..109]
    output += " */#{EOL}#{EOL}"
    output

  # Cleverly find and replace fingerprinted assets URLs in CSS files
  _replaceCssUrls: (sourceFile, contents) ->
    contents = contents.replace CSS_URL_REGEX, (all, file, suffix) =>
      absFilePath = path.resolve @src, path.dirname(sourceFile), file
      for own asset, config of @config when config.action is 'copy'
        absSourcePath = path.resolve @src, config.sources[0].file
        return "url(\"#{@pfx}#{config.destination}#{suffix}\")" if absSourcePath is absFilePath
      all
    contents

  # Build an asset and write the output file in the destination folder
  _buildAsset: (asset, config, callback) ->
    dst    = path.resolve @dst, config.destination
    ext    = path.extname(asset).toLowerCase()
    output = ''
    last   = config.sources.length - 1

    for source, i in config.sources
      sourceFile     = source.file
      sourceFullPath = path.resolve @src, sourceFile
      sourceExt      = path.extname(sourceFile).toLowerCase()
      if sourceExt in ['.js', '.css']
        # JS & CSS files are simply read
        await fs.readFile sourceFullPath, 'utf8', defer err, contents
        return callback err if err
      else
        # Look for a specific ASPAX plugin to compile the asset
        try
          plugin = require path.resolve 'node_modules', "aspax-#{sourceExt[1..]}-handler"
        catch err
          return callback err
        await plugin.compile sourceFullPath, source.flags, defer err, contents
        return callback err if err

      # Adjust URLs in CSS files
      contents = @_replaceCssUrls sourceFile, contents if ext is '.css'

      # Add a header for each asset component; might be helpful for debugging
      output += @_getSourceHeader(sourceFile) + contents
      output += EOL + EOL unless i is last

    # Minimize as needed
    if config.min
      output = uglify.minify(output, fromString: yes).code if ext is '.js'
      output = csso.minify(output, restructure: no).css    if ext is '.css'

    dir = path.dirname dst
    await fs.exists dir, defer exists
    unless exists
      await ft.mkdir dir, defer err
      callback err if err
    await fs.writeFile dst, output, defer err
    callback err

  # Copy an asset from source folder to destination folder
  _copyAsset: (asset, config, callback) ->
    src = path.resolve @src, config.sources[0].file
    dst = path.resolve @dst, config.destination
    await ft.copy src, dst, defer err
    callback err

  # Continuously watch for changes and rebuild as needed
  watch: ->
    await @build 'dev', defer()
    await @_buildTriggers asset, config, defer() for own asset, config of @config

    console.log clc.yellow "#{EOL}watching #{@src} for file changes (press ^C to exit)..."
    process.on 'SIGINT', ->
      console.log clc.yellow "#{EOL}exiting..."
      process.exit()

    await gaze "#{@src}/**/*", { mode: 'poll', interval: 1000, debounceDelay: 500 }, defer err, watcher

    watcher.on 'error', (e) -> console.log clc.yellow "#{e}... maybe you should restart?..."

    watcher.on 'changed', (file) =>
      if file is @configFile
        console.log clc.yellow "#{EOL}#{CONFIG_FILE_BASENAME} changed, restarting...#{EOL}"
        watcher.close()
        @watch()
      else
        processed = no
        for own asset, config of @config
          for trigger in config.triggers when trigger is file
            await @_buildTriggers asset, config, defer()
            process.stdout.write clc.white "#{config.action}ing #{asset}... "
            await @["_#{config.action}Asset"] asset, config, defer err
            console.log if err then clc.red 'failed with: ', err else clc.green 'done...'
            processed = yes
            break
        console.log clc.yellow 'Unhandled file change detected... maybe you should restart?...' unless processed

  # Build assets; mode = dev|prod
  build: (mode = 'dev', callback) ->
    await @clean defer()
    process.stdout.write clc.yellow "loading #{CONFIG_FILE_BASENAME} from #{@src}... "
    await @_buildConfig mode, defer err
    console.log if err then clc.red 'failed with: ', err else clc.green 'done...'
    map = {}
    for own asset, config of @config
      action = config.action
      process.stdout.write clc.white "#{action}ing #{asset}... "
      await @["_#{action}Asset"] asset, config, defer err
      console.log if err then clc.red 'failed with: ', err else clc.green 'done...'
      map[asset] = "#{@pfx}#{config.destination}"
    process.stdout.write clc.white "writing #{@out}... "
    contents = if path.extname(@out) is '.yml' then yml.dump(map) else JSON.stringify(map, null, '\t')
    await fs.writeFile @out, contents, defer err
    console.log if err then clc.red 'failed with: ', err else clc.green 'done...'
    callback() if callback

  # Build assets for production
  pack: -> @build 'prod'

  # Clean destination folder and output map (aspax.json or aspax.yml)
  clean: (callback) ->
    process.stdout.write clc.yellow "cleaning #{@dst} folder and removing #{@out}... "
    await ft.remove @dst, defer err
    console.log clc.red 'failed with: ', err if err
    await ft.mkdir @dst, defer err
    console.log clc.red 'failed with: ', err if err
    await fs.exists @out, defer exists
    if exists
      await fs.unlink @out, defer err
      console.log clc.red 'failed with: ', err if err
    console.log clc.green 'done...'
    callback() if callback

module.exports = (args...) -> new AspaX args...
