runtime syntax/dosini.vim

syn clear dosiniHeader
syn clear dosiniComment
syn match TaskComment  "^;.*$"
syn region TaskName   start="^\s*\[" end="\]" contains=TaskOs nextgroup=TaskTag
syn match TasksError '^[^;\[]\+\ze=\?.*'
syn match TaskTag '\s\+@\w\+' contained nextgroup=TaskTag

let s:cmd  = '%(<command>(:(\w+,?)+)?(\/(\w+,?)+)?)'
let s:keys = [
            \'cwd', 'output', 'compiler',
            \'success', 'fail', 'syntax',
            \'errorformat', 'grepformat',
            \'options', 'args',
            \'outfile', 'errfile',
            \'name', 'description',
            \]
exe printf("syn match TasksField '\\v\\C^%s|<%s>|<[A-Z_]+>\\ze\\=.+'", s:cmd, join(s:keys, '>|<'))

syn match TasksSect   '^#\(\<env\>\|\<environment\>\|\<info\>\)'
syn match TasksEnvVar '\${\?[A-Z_]\+}\?' containedin=dosiniValue
syn match TasksEnvVar '\%(\%(Windows\|\<win\d\d\>\).\{-}\)\@<=%[A-Z_]\+%' containedin=dosiniValue
syn match TaskVimCmd  '=\zsVIM: ' containedin=dosiniValue nextgroup=TaskVimEx
syn match TaskVimEx   '.*' contained
syn match TaskOs      '/\zs.*\ze]' contained

hi default link TasksSect   Constant
hi default link TasksEnvVar Identifier
hi default link TasksError  WarningMsg
hi default link TasksField  dosiniLabel
hi default link TaskName    Special
hi default link TaskTag     Constant
hi default link TaskComment Comment
hi default link TaskVimCmd  Special
hi default link TaskVimEx   String
hi default link TaskOs      Identifier
