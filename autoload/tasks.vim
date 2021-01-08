" ========================================================================///
" Description: Tasks management inspired by asynctasks.vim
" File:        tasks.vim
" Author:      Gianmaria Bajo <mg1979@git.gmail.com>
" License:     MIT
" Created:     mar 08 settembre 2020 01:58:09
" Modified:    mar 08 settembre 2020 01:58:09
" ========================================================================///


"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Tasks getters
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

""
" Get valid tasks, fetched from both global and project-local config files.
" Configuration files are parsed, then merged. Tasks are a nested, so they will
" have to be merged independently, giving precedence to project-local tasks.
" If in a managed project, allow global tasks if they have the 'always' tag.
"
" @param ...: force reloading of config files
" @return: the merged dictionary with tasks
""
function! tasks#get(...) abort
    " known tags will be regenerated
    let g:tasks['__known_tags__'] = ['default']
    let reload = a:0 && a:1
    let global = deepcopy(tasks#global(reload))
    let local = deepcopy(tasks#project(reload))
    let gtasks = deepcopy(global.tasks)
    let genv = copy(global.env)
    if !empty(local)
        call filter(gtasks, "v:val.always")
    endif
    let all = extend(global, local)
    call extend(all.tasks, gtasks, 'keep')
    call extend(all.env, genv, 'keep')
    return all
endfunction


""
" Get the project-local tasks dictionary.
""
function! tasks#project(reload) abort
    let prj = s:ut.basedir()
    if !a:reload && has_key(g:tasks, prj)
        return g:tasks[prj]
    endif
    let f = s:get_local_ini()
    if !filereadable(f)
        return {}
    endif
    let g:tasks[prj] = tasks#parse#do(readfile(f), 1)
    return g:tasks[prj]
endfunction


""
" Get the global tasks dictionary.
""
function! tasks#global(reload) abort
    if !a:reload && has_key(g:tasks, 'global')
        return g:tasks.global
    endif
    let f = s:get_global_ini()
    if !filereadable(f)
        return {}
    endif
    let g:tasks.global = tasks#parse#do(readfile(f), 0)
    return g:tasks.global
endfunction


" TODO: :Project, :Compile commands
" TODO: test environmental variables expansion
" TODO: assign score to commands to see which one should be chosen
" TODO: cwd, prjname
" TODO: success/fail hooks



"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Run task
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

""
" Main command to run a task. Will call async#cmd.
""
function! tasks#run(args) abort
    redraw
    let prj = tasks#get()
    if empty(prj)
        let root = s:find_root()
        if s:change_root(root)
            lcd `=root`
            let prj = tasks#get()
        endif
    endif
    if s:no_tasks(prj)
        return
    endif
    let tasks = prj.tasks
    let a = split(a:args)
    let name = a[0]
    let args = len(a) > 1 ? join(a[1:]) : ''

    if !has_key(tasks, name)
        echon s:ut.badge() 'not a valid task'
        return
    endif

    let task = tasks[name]
    let cmd = s:choose_command(task)

    if cmd =~ '^VIM: '
        call s:execute_vim_command(cmd, args)
        return
    endif

    let mode = s:get_cmd_mode(task)
    let opts = extend(s:get_pos(mode),
                \     s:get_opts(get(task.fields, 'options', [])))
    let useropts = extend({
                \ 'prg': cmd,
                \ 'gprg': cmd,
                \ 'efm': get(task.fields, 'efm', &errorformat),
                \ 'compiler': get(task.fields, 'compiler', ''),
                \ 'ft': get(task.fields, 'syntax', ''),
                \}, opts)
    let jobopts = {
                \ 'env': prj.env,
                \ 'cwd': s:get_cwd(prj, task),
                \}
    let mode = substitute(mode, ':.*', '', '')
    if mode == 'quickfix'
        call async#qfix(args, useropts, jobopts)
    else
        call async#cmd(cmd . ' ' . args, mode, useropts, jobopts)
    endif
endfunction

""
" It's a vim command, execute as-is.
""
function! s:execute_vim_command(cmd, args)
    if a:args != ''
        execute substitute(a:cmd . ' ' . a:args, '^VIM: ', '', '')
    else
        execute substitute(a:cmd, '^VIM: ', '', '')
    endif
endfunction

""
" Choose the most appropriate command for the task.
""
function! s:choose_command(task) abort
    let [cmdpat, cmppat, ft] = ['^command', '^compiler', '\<' . s:ut.ft() . '\>']

    " try 'compiler' first, then 'command'
    let cmds = filter(copy(a:task.fields), 'v:key =~ cmppat')
    if empty(cmds)
        let cmds = filter(copy(a:task.fields), 'v:key =~ cmdpat')
    endif
    " loop all the commands and choose the one with the highest score
    " score is based on specificity for system (/) and filetype (:)
    " best has elements: [key, command, score]
    let best = ['', '', 0]
    for key in keys(cmds)
        let score = (key =~ '/') + (key =~ ':')
        if score >= best[2]
            let best = [key, cmds[key], score]
        endif
    endfor

    " clear all commands from task, the chosen command will be set instead
    call filter(a:task.fields, 'v:key !~ cmdpat')
    call filter(a:task.fields, 'v:key !~ cmppat')
    if best[1] != ''
        let a:task.fields[best[0]] = best[1]
        return best[1]
    endif
    return &makeprg
endfunction

""
" If the task defines a cwd, it should be expanded.
" Expand also $ROOT and $PRJNAME because they aren't set in vim environment.
""
function! s:get_cwd(prj, task) abort
    if has_key(a:task.fields, 'cwd')
        let cwd = async#expand(a:task.fields.cwd)
        if s:v.is_windows
            let cwd = substitute(cwd, '%\([A-Z_]\+\)%', '$\1', 'g')
        endif
        if a:task.local
            let cwd = s:expand_builtin_envvars(cwd, a:prj)
        endif
        let cwd = substitute(cwd, '\(\$[A-Z_]\+\)\>', '\=expand(submatch(1))', 'g')
        return cwd
    else
        return getcwd()
    endif
endfunction

""
" Returns task command with expanded env variables and vim placeholders.
""
function! s:expand_task_cmd(task, prj)
    let cmd = async#expand(s:choose_command(a:task))
    if a:task.local
        let cmd = s:expand_builtin_envvars(cmd, a:prj)
    endif
    return cmd
endfunction

""
" Expand built-in variables $ROOT and $PRJNAME.
""
function! s:expand_builtin_envvars(string, prj) abort
    let s = substitute(a:string, '\$ROOT\>', '\=getcwd()', 'g')
    let s = substitute(s, '\$PRJNAME\>', '\=a:prj.info.name', 'g')
    return s
endfunction

""
" Mode is either 'quickfix', 'buffer', 'terminal', 'external' or 'cmdline'.
""
function! s:get_cmd_mode(task) abort
    let mode = filter(copy(a:task.fields), { k,v -> k =~ '^output' })
    return len(mode) > 0 ? values(mode)[0] : 'quickfix'
endfunction

""
" Buffer and terminal modes can define position after ':'
""
function! s:get_pos(mode) abort
    if a:mode !~ '\v^(buffer|terminal):'.s:v.pospat
        return {}
    else
        return {'pos': substitute(a:mode, '^\w\+:', '', '')}
    endif
endfunction

""
" All options have a default of 0.
" Options defined in the 'options' field will be set to 1.
""
function! s:get_opts(opts) abort
    let opts = {}
    for v in a:opts
        let opts[v] = 1
    endfor
    return opts
endfunction

""
" Command line completion for tasks.
""
function! tasks#complete(A, C, P) abort
    let valid = keys(get(tasks#get(), 'tasks', {}))
    return filter(sort(valid), 'v:val=~#a:A')
endfunction


"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" List tasks
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

""
" Display tasks in the command line, or in json format.
""
function! tasks#list(as_json) abort
    let prj = tasks#get(1)
    if s:no_tasks(prj)
        return
    endif
    if a:as_json
        call s:tasks_as_json(prj)
        return
    endif
    call s:cmdline_bar(prj)
    echohl Comment
    echo "Task\t\t\t\tTag\t\tOutput\t\tCommand"
    for t in sort(keys(prj.tasks))
        let T = prj.tasks[t]
        ""
        " --------------------------- [ task name ] ---------------------------
        ""
        echohl Constant
        echo t . repeat(' ', 32 - strlen(t))
        ""
        " --------------------------- [ task tag ] ----------------------------
        ""
        echohl String
        let p = T.tag == 'default'
                    \ ? T.local ? 'project' : 'global'
                    \ : T.tag
        echon p . repeat(' ', 16 - strlen(p))
        ""
        " -------------------------- [ output type ] --------------------------
        ""
        echohl PreProc
        let out = split(get(T.fields, 'output', 'quickfix'), ':')[0]
        echon out . repeat(' ', 16 - strlen(out))
        ""
        " ------------------------- [ task command ] -------------------------
        ""
        echohl None
        let cmd = s:expand_task_cmd(T, prj)
        let n = &columns - 66 < strlen(cmd) ? '' : 'n'
        exe 'echo' . n string(cmd)
    endfor
    echohl None
endfunction

""
" Top bar for command-line tasks list.
""
function! s:cmdline_bar(prj) abort
    echohl QuickFixLine
    let header = has_key(a:prj, 'info') ?
                \'Project: '. a:prj.info.name : 'Global tasks'
    let right   = repeat(' ', &columns - 10 - strlen(header))
    echon '      ' . header . '   ' . right
endfunction

""
" Display tasks in a buffer, in json format.
""
function! s:tasks_as_json(prj) abort
    let py =        executable('python3') ? 'python3'
                \ : executable('python')  ? 'python' : ''
    if py == ''
        echon s:ut.badge() 'no python executable found in $PATH'
        return
    endif
    let [ft, f] = [&ft, @%]
    let json = json_encode(a:prj)
    vnew +setlocal\ bt=nofile\ bh=wipe\ noswf\ nobl
    silent! XTabNameBuffer Tasks
    wincmd H
    put =json
    1d _
    exe '%!' . py . ' -m json.tool'
    setfiletype json
    let &l:statusline = '%#PmenuSel# Tasks %#Pmenu# ft=' .
                \       ft . ' %#Statusline# ' . f
endfunction



"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Choose task with mapping
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

""
" Choose among available tasks (called with mapping).
" @param ...: prompt for extra args
""
function! tasks#choose(...) abort
    let prj = tasks#get(1)
    if s:no_tasks(prj)
        return
    endif
    let use_F = get(g:, 'tasks_mapping_use_Fn_keys', 6)
    if use_F && len(keys(prj.tasks)) == 1
        let f = substitute("\<F6>", '6$', use_F, '')
        let Keys = { 1: f}
        let l:PnKey = { c -> '<F'. use_F .'>' . "\t"}
    elseif use_F && len(keys(prj.tasks)) <= 8
        let Keys = { 1: "\<F5>", 2: "\<F6>", 3: "\<F7>", 4: "\<F8>",
                    \5: "\<F9>", 6: "\<F10>", 7: "\<F11>", 8: "\<F12>"}
        let l:PnKey = { c -> '<F'.(c+4).'>' . "\t"}
    elseif use_F && len(keys(prj.tasks)) <= 12
        let Keys = { 1: "\<F1>", 2: "\<F2>", 3: "\<F3>", 4: "\<F4>",
                    \5: "\<F5>", 6: "\<F6>", 7: "\<F7>", 8: "\<F8>",
                    \9: "\<F9>", 10: "\<F10>", 11: "\<F11>", 12: "\<F12>"}
        let l:PnKey = { c -> '<F'.c.'>' . "\t"}
    else
        let Keys = {}
        for i in range(1, 26)
            let Keys[i] = nr2char(96 + i)
        endfor
        let l:PnKey = { c -> Keys[c] . "\t"}
    endif
    let dict = {}
    let i = 1
    call s:cmdline_bar(prj)
    echohl Comment
    echo "Key\tTask\t\t\t\tTag\t\tOutput\t\tCommand"
    for t in sort(keys(prj.tasks))
        let T = prj.tasks[t]
        let dict[Keys[i]] = t
        ""
        " ---------------------------- [ mapping ] ----------------------------
        ""
        echohl Special
        echo l:PnKey(i)
        ""
        " --------------------------- [ task name ] ---------------------------
        ""
        echohl Constant
        echon t . repeat(' ', 32 - strlen(t))
        ""
        " --------------------------- [ task tag ] ----------------------------
        ""
        echohl String
        let p = T.tag == 'default'
                    \ ? T.local ? 'project' : 'global'
                    \ : T.tag
        echon p . repeat(' ', 16 - strlen(p))
        ""
        " -------------------------- [ output type ] --------------------------
        ""
        echohl PreProc
        let out = split(get(T.fields, 'output', 'quickfix'), ':')[0]
        echon out . repeat(' ', 16 - strlen(out))
        ""
        " ------------------------- [ task command ] -------------------------
        ""
        echohl None
        let cmd = s:expand_task_cmd(T, prj)
        if &columns - 84 < strlen(cmd)
            let cmd = cmd[:(&columns - 84)] . '…'
        endif
        echon cmd
        let i += 1
    endfor
    echo ''
    let ch = getchar()
    let ch = ch > 0 ? nr2char(ch) : ch
    if index(keys(dict), ch) >= 0
        if a:0
            redraw
            echohl Delimiter  | echo 'Command: ' | echohl None
            echon s:expand_task_cmd(prj.tasks[dict[ch]], prj)
            let args = input('args: ')
            if empty(args) && confirm('Run with no arguments?', "&Yes\n&No") != 1
                redraw
                echo 'Canceled'
                return
            endif
        else
            let args = ''
        endif
        exe 'Task' dict[ch] args
    else
        redraw
    endif
endfunction




"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Get configuration files
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

""
" Path for the global configuration.
""
function! s:get_global_ini() abort
    if exists('s:global_ini') && s:global_ini != ''
        return s:global_ini
    endif

    let f = get(g:, 'async_taskfile_global', 'tasks.ini')
    let l:In = { dir -> filereadable(expand(dir).'/'.f) }
    let l:Is = { dir -> expand(dir).'/'.f }

    let s:global_ini = has('nvim') &&
                \ l:In(stdpath('data'))  ? l:Is(stdpath('data')) :
                \ l:In('$HOME/.vim')     ? l:Is('$HOME/.vim') :
                \ l:In('$HOME/vimfiles') ? l:Is('$HOME/vimfiles') : ''

    if s:global_ini == ''
        let dir = fnamemodify(expand($MYVIMRC), ':p:h')
        if filereadable(dir . '/' . f)
            let s:global_ini = dir . '/' . f
        endif
    endif
    return s:global_ini
endfunction

""
" Path for the project configuration.
""
function! s:get_local_ini() abort
    return get(g:, 'async_taskfile_local', '.tasks')
endfunction



"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Helpers
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

""
" No tasks available for current project/filetye
""
function! s:no_tasks(prj) abort
    if empty(a:prj) || empty(a:prj.tasks)
        echon s:ut.badge() 'no tasks'
        return v:true
    endif
    return v:false
endfunction

""
" Search recursively for a local tasks file in parent directories.
""
function! s:find_root() abort
    let dir = expand('%:p:h')
    let fname = s:get_local_ini()
    while v:true
        if filereadable(dir . '/' . fname )
            return dir
        elseif fnamemodify(dir, ':p:h:h') == dir
            break
        else
            let dir = fnamemodify(dir, ':p:h:h')
        endif
    endwhile
    return v:null
endfunction

""
" Confirm root change.
""
function! s:change_root(root) abort
    return a:root != v:null &&
                \ confirm('Change directory to ' . a:root . '?', "&Yes\n&No") == 1
endfunction





"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Script variables
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

let s:ut = tasks#util#init()
let s:v  = s:ut.Vars



"""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" vim: et sw=4 ts=4 sts=4 fdm=indent fdn=1
