" ========================================================================///
" Description: Run asynch commands
" Author:      Gianmaria Bajo ( mg1979@git.gmail.com )
" File:        async.vim
" License:     MIT
" Modified:    lun 07 ottobre 2019 07:19:25
" ========================================================================///

"GUARD {{{1
if exists('g:loaded_async')
  finish
endif
let g:loaded_async = 1
"}}}

" Async:     Run a shell command asynchronously in headless mode.
" AsyncBuf:  Run a shell command asynchronously and print output in a buffer.
" AsyncCmd:  Echo the output of an asynchronous shell command to the command line.
" StopJobs:  Stop all jobs. With a bang, jobs are killed (vim only).
" Jobs:      List all running jobs. List finished jobs with BANG.
" Make:      Run :make asynchronously.
" LMake:     ,,  :lmake   ,,
" Grep:      ,,  :grep    ,,
" LGrep:     ,,  :lgrep   ,,
" GrepAdd:   ,,  :grepadd ,,
" LGrepAdd:  ,,  :grepadd ,,
"
" System, Async and Echo accept a BANG (will write out/err to temp files).
" For Make/Grep commands, with BANG will not jump to the first error/match, and
" will not open the qfix window.

let g:async_default_opts = {}

command! -nargs=1 -bang AsyncBuf  call async#cmd(<q-args>, 'buffer', {'writelogs': <bang>0})
command! -nargs=1 -bang AsyncCmd  call async#cmd(<q-args>, 'cmdline', {'writelogs': <bang>0})
command! -nargs=1 -bang Async     call async#cmd(<q-args>, 'headless', {'writelogs': <bang>0})

command! -bang          StopJobs  call async#stop(0, <bang>0)
command! -bang          Jobs      call async#list(<bang>0)

command! -nargs=? -bang -complete=customlist,async#make#complete Make      call async#qfix(<q-args>, {'nojump': <bang>0})
command! -nargs=? -bang -complete=customlist,async#make#complete LMake     call async#qfix(<q-args>, {'nojump': <bang>0, 'locl': 1})

command! -nargs=1 -bang -complete=compiler Compiler  call async#compiler(<q-args>, {'nojump': <bang>0})
command! -nargs=1 -bang -complete=compiler LCompiler call async#compiler(<q-args>, {'nojump': <bang>0, 'locl': 1})

command! -nargs=1 -bang Grep      call async#qfix(<q-args>, {'nojump': <bang>0, 'grep': 1})
command! -nargs=1 -bang LGrep     call async#qfix(<q-args>, {'nojump': <bang>0, 'grep': 1, 'locl': 1})
command! -nargs=1 -bang GrepAdd   call async#qfix(<q-args>, {'nojump': <bang>0, 'grep': 1, 'append': 1})
command! -nargs=1 -bang LGrepAdd  call async#qfix(<q-args>, {'nojump': <bang>0, 'grep': 1, 'locl': 1, 'append': 1})

" vim: et sw=2 ts=2 sts=2 fdm=marker
