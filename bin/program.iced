path    = require 'path'

program = require 'commander'
clc     = require 'cli-color'
aspax   = require '../aspax.iced'

program
  .version(require('../package.json').version)
  .usage('-s <source> [-d <destination>] [-p <public>] [-o <aspax.json>] [watch|clean|build|pack]')
  .option('-s, --src <source>',      'Assets source folder')
  .option('-d, --dst <destination>', 'Assets destination folder, defaults to public in current folder')
  .option('-p, --pfx <prefix>',      'Assets destination prefix, defaults to /')
  .option('-o, --out <aspax.json>',  'Output map in json or yml format, defaults to aspax.json in current folder')
  .parse process.argv

program.dst   or= 'public'
program.pfx   or= '/'
program.out   or= 'aspax.json'
action        = if program.args.length then program.args[0] else 'watch'
actionIsValid = action in ['watch', 'clean', 'build', 'pack']
outExtIsValid = path.extname(program.out).toLowerCase() in ['.json', '.yml']

if program.src and outExtIsValid and actionIsValid
  aspax(program.src, program.dst, program.pfx, program.out)[action]()
else
  console.log clc.red 'Please specify assets source folder.' unless program.src
  console.log clc.red 'Valid output map types are json and yml.' unless actionIsValid
  console.log clc.red 'Valid actions are watch (default if not specified), clean and build.' unless actionIsValid
  console.log 'Check aspax --help for more info.'
