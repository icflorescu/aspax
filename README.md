## The simple Node.js asset packager
ASPAX is a simple command-line utility able to watch, compile, concatenate, minify, compress and fingerprint web assets by interpreting a simple config file written in clear, human-readable YML syntax:

`aspax.yml`:
```yaml
js/app.js|fp|min|gz:
  - lib/bootstrap/js/bootstrap.js
  - lib/moment.js
  - lib/jade/runtime.js
  - scripts/namespaces.coffee|bare
  - templates/item.jade
  - scripts/index.ls|bare

css/app.css|fp|min|gz:
  - lib/bootstrap/css/bootstrap.css
  - lib/bootstrap/css/bootstrap-theme.css
  - styles/index.styl|nib

favicon.png:               images/favicon.png

fonts/bs-glyphs.eot|fp:    lib/bootstrap/fonts/glyphicons-halflings-regular.eot
fonts/bs-glyphs.svg|fp|gz: lib/bootstrap/fonts/glyphicons-halflings-regular.svg
fonts/bs-glyphs.ttf|fp|gz: lib/bootstrap/fonts/glyphicons-halflings-regular.ttf
fonts/bs-glyphs.woff|fp:   lib/bootstrap/fonts/glyphicons-halflings-regular.woff
```

That's it. No complicated `.initConfig()`, no redundant code to describe tasks in JavaScript or CoffeeScript.

By looking at that file, ASPAX will:

- watch the folder and rebuild **just the necessary files** on changes;
- compile, concatenate and copy files in development mode;
- compile, concatenate, minify, compress, fingerprint and copy files in production mode.

## Installation
Most likely you'll want ASPAX installed as a global module:

    npm install aspax -g

## Source handlers
To keep the global CLI module lightweight and dependency-free, ASPAX is using a plugin system to handle different source types such as CoffeeScript, LiveScript, client-side Jade templates, Stylus or LESS files, etc.

ASPAX will look for plugins in `./node_modules` folder, so you'll have to install the necessary source handlers like this:

    npm install aspax-coffee-handler --save-dev

If you're running ASPAX in a Node.js application root folder, consider using the `--save-dev` option to avoid deploying the plugins to your production environment:

    npm install aspax-coffee-handler --save-dev

### Available source handlers
So far:

- [aspax-coffee-handler](http://github.com/icflorescu/aspax-coffee-handler) for [CoffeeScript](http://coffeescript.org);
- [aspax-iced-handler](http://github.com/icflorescu/aspax-iced-handler) for [IcedCoffeeScript](http://maxtaco.github.io/coffee-script);
- [aspax-ls-handler](http://github.com/icflorescu/aspax-ls-handler) for [LiveScript](http://livescript.net);
- [aspax-jade-handler](http://github.com/icflorescu/aspax-jade-handler) for client-side [Jade](http://jade-lang.com) templates;
- [aspax-styl-handler](http://github.com/icflorescu/aspax-styl-handler) for [Stylus](http://learnboost.github.io/stylus);
- [aspax-less-handler](http://github.com/icflorescu/aspax-less-handler) for [LESS](http://lesscss.org).

If you need something else, please let me know and maybe I can do it, or better yet, feel free to do it yourself and notify me so I can list it here.

### Developing additional source handlers
Each source handler npm should be named 'aspax-xyz-handler', where 'xyz' is the file extension it refers to.

Each npm should export a `compile()` method with this signature (see example [here](https://github.com/icflorescu/aspax-coffee-handler/blob/master/plugin.coffee)):

```js
exports.compile = function(file, flags, callback) {
  ...
};
```

...and optionally a `findImports()` method to recursively find imported/referred files (see examples [here](https://github.com/icflorescu/aspax-less-handler/blob/master/plugin.iced)) and [here](https://github.com/icflorescu/aspax-jade-handler/blob/master/plugin.iced)):

    exports.findImports = function(imports, file, callback) {
      ...
    };

## Usage
CLI usage samples:

    # watch and build on-the-fly during development
    aspax -s ../assets watch

    # build for development
    aspax -s ../assets build

    # pack for production (will compile, concat, minify, compress and fingerprint)
    aspax -s ../assets pack

    # clean everything
    aspax -s ../client clean

Type `aspax --help` in the console to see more info:

    Usage: aspax -s <source> [-d <destination>] [-p <public>] [-o <aspax.json>] [watch|clean|build|pack]

    Options:

      -h, --help               output usage information
      -V, --version            output the version number
      -s, --src <source>       Assets source folder
      -d, --dst <destination>  Assets destination folder, defaults to public in current folder
      -p, --pfx <prefix>       Assets destination prefix, defaults to /
      -o, --out <aspax.json>   Output map in json or yml format, defaults to aspax.json in current folder

### Using assets built and packaged by ASPAX in an Express.js application
See [aspax-express](http://github.com/icflorescu/aspax-express) - there's a nice step-by-step guide in the project readme.

In addition, you can have a look at [this demo repository](https://github.com/icflorescu/aspax-demo) to see a ready-made setup.

## Config file syntax
The syntax of `aspax.yml` should be quite simple and human-friendly. Here are just a few tips:

### Marking assets for fingerprinting, minifying and compressing
Just add the appropriate **flags** after the asset file name (the order is irrelevant):

                ┌─────────────┐
              ┌─┤ fingerprint │
              │ └─────────────┘
              │      ┌────────┐
              │  ┌───┤ minify │
              │  │   └────────┘
              │  │     ┌──────┐
              │  │   ┌─┤ gzip │
              │  │   │ └──────┘
              ┴─ ┴── ┴─
    js/app.js|fp|min|gz:
      - ...

The **flags** will have no effect in development mode, but in production:

- marking an asset for fingerprinting will add an UNIX timestamp like `-1387239833024` before its extension;
- marking an asset for minifying will process it with [UglifyJS2](https://github.com/mishoo/UglifyJS2)/[CSS-optimizer](https://github.com/css/csso) and will also add `.min` before the extension;
- marking an asset for compression will gzip it and also add a `.gz` suffix to its name.

Notes:

- fingerprinting and compressing will work for anything, while minifying only makes sense for JS and CSS files;
- there's no point, of course, in trying to compress already compressed formats such as `.jpg`, `.png` or `.eot`.

### Source handler flags
Some source-handling plugins are also accepting **flags** (i.e. `bare` for CoffeeScript files). Use the same syntax:

       ┌─────────────────────┐
       │ compile without the │
       │ top-level function  ├──┐
       │ safety wrapper      │  │
       └─────────────────────┘  │
                                │
      - ...                   ──┴─
      - scripts/source.coffee|bare
      - ...

## FAQ

### What's the meaning of the name?
**AS**set **PA**ckager, and **X** because ASPAX is an evolution of [ASPA](http://github.com/icflorescu/aspa), a similar module I've built in the past.

### So why writing ASPAX instead of just updating [ASPA](http://github.com/icflorescu/aspa)?
ASPAX brings in some breaking changes by simplifying the YML file syntax and introducing a plugin system to handle various source files. Simply upgrading [ASPA](http://github.com/icflorescu/aspa) wouldn't be possible without annoying the happiness of too many users.

## Endorsing the author
If you find this piece of software useful, please [![endorse](https://api.coderwall.com/icflorescu/endorsecount.png)](https://coderwall.com/icflorescu) me on Coderwall!
