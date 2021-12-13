if empty(glob('~/.vim/autoload/plug.vim'))
	silent !curl -fLo ~/.vim/autoload/plug.vim --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
	autocmd VimEnter * PlugInstall --sync | source $MYVIMRC
endif

" Specify a directory for plugins
" - For Neovim: ~/.local/share/nvim/plugged
" - Avoid using standard Vim directory names like 'plugin'
" curl -fLo ~/.vim/autoload/plug.vim --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
call plug#begin('~/.vim/plugged')

Plug 'scrooloose/nerdtree', { 'on': 'NERDTreeToggle' }
Plug 'editorconfig/editorconfig-vim'
Plug 'rakr/vim-one'
Plug 'vim-airline/vim-airline'
Plug 'vim-airline/vim-airline-themes'
Plug 'vim-python/python-syntax'
Plug 'chriskempson/tomorrow-theme'
Plug 'octol/vim-cpp-enhanced-highlight'
"Plug 'vivien/vim-linux-coding-style'

Plug 'skywind3000/asyncrun.vim'
"Plug 'w0rp/ale'
Plug 'Yggdroot/LeaderF'
Plug 'machakann/vim-highlightedyank'

"Google vim-codefmt
Plug 'google/vim-maktaba'
" Plug 'crazyboycjr/vim-codefmt'
Plug 'crazyboycjr/vim-codefmt'

"vim-go
Plug 'fatih/vim-go'

" haskell indent, just put this before haskell-vim
Plug 'itchyny/vim-haskell-indent'
" haskell-vim
Plug 'neovimhaskell/haskell-vim'

Plug 'alx741/vim-hindent'

"Plug 'rhysd/vim-clang-format'

Plug 'neoclide/coc.nvim', {'branch': 'release'}

Plug 'rust-lang/rust.vim'

Plug 'gruvbox-community/gruvbox'

Plug 'LnL7/vim-nix'

" All of your Plugins must be added before the following line
call plug#end()
filetype plugin indent on	" required


set tags=./tags,tags;$HOME
if filereadable("cscope.out")
	cs add cscope.out
elseif $CSOPE_DB != ""
	cs add $CSOPE_DB
endif

"set backupdir-=.
"set backupdir^=/tmp
"set undodir-=.
"set undodir^=/tmp

syntax on
set nu rnu
"set cindent
set nowrap
set si
set sw=4
set sts=4
set ts=4
set incsearch
set hlsearch
set mouse=a
set ttimeout		" time out for key codes
set ttimeoutlen=0	" wait up to 0ms after Esc for special key
set splitright
set splitbelow
set wildmode=longest,list
if !has('nvim')
	set ttymouse=sgr
endif

autocmd filetype c,h,lex,yacc setlocal sts=8 ts=8 sw=8
autocmd filetype cpp,hpp,cuda setlocal sts=2 ts=2 sw=2 expandtab
"autocmd filetype python setlocal ts=4 sw=4 sts=4 expandtab
autocmd filetype javascript setlocal ts=2 sw=2 sts=0 noexpandtab
autocmd filetype css,html,htmldjango setlocal sts=2 ts=2 sw=2 expandtab
autocmd filetype haskell setlocal expandtab
autocmd filetype cmake setlocal sts=4 ts=4 sw=4 expandtab

autocmd BufNewFile,BufRead *.toml,Gopkg.lock,Cargo.lock,*/.cargo/config,*/.cargo/credentials,Pipfile set filetype=toml
autocmd filetype toml setlocal sts=2 ts=2 sw=2 expandtab
autocmd filetype rust set colorcolumn=100 sts=4 sw=4 ts=4 expandtab
autocmd filetype tex setlocal spell tw=80 colorcolumn=81
autocmd filetype text setlocal spell tw=72 colorcolumn=73
autocmd filetype markdown setlocal spell tw=72 colorcolumn=73
autocmd filetype gitcommit setlocal spell tw=72 colorcolumn=73


augroup autoformat_settings
	autocmd FileType bzl AutoFormatBuffer buildifier
	"autocmd FileType cpp,proto,javascript AutoFormatBuffer clang-format
	autocmd FileType go AutoFormatBuffer gofmt
	"autocmd FileType json AutoFormatBuffer js-beautify
	"autocmd FileTYpe python AutoFormatBuffer yapf
augroup END

" reliative number
augroup numbertoggle
	autocmd!
	autocmd BufEnter,FocusGained,InsertLeave * set relativenumber
	autocmd BufLeave,FocusLost,InsertEnter	* set norelativenumber
augroup END

" set cursorline
nnoremap <Leader>c :set cursorline!<CR>
augroup CursorLine
	autocmd!
	autocmd VimEnter,WinEnter,BufWinEnter * setlocal cursorline
	autocmd WinLeave * setlocal nocursorline
augroup END

if has("nvim")
	" nmap <F24> <S-F12>
	" nmap <F29> <C-F5>
	for i in range(1, 12)
		let j = i + 12
		let k = i + 24
		exec "nmap <F".j."> <S-F".i.">"
		exec "nmap <F".k."> <C-F".i.">"
	endfor
	" :help last-position-jump
	autocmd BufReadPost *
	  \ if line("'\"") >= 1 && line("'\"") <= line("$") |
	  \   exe "normal! g`\"" |
	  \ endif
	if exists(':tnoremap')
		tnoremap <Esc> <C-\><C-n>
	endif
	" Enter insert mode automatically when terminal open
	autocmd TermOpen * startinsert
	" Probably the scrollback buffer to maximum
	set scrollback=100000
endif

" Compile various languages
func! DoMake()
" This function search its super directory to find a Makefile until
" this directory contains .git
	exec "wa"
	let s:name = "Makefile"
	let vdir = "./"
	let s:flag = 1
	while filereadable(vdir . s:name) == 0
		if filereadable(vdir . ".git") != 0
			s:flag = 0
			break
		endif
		let vdir = "../" . vdir
	endwhile
	unlet s:name
	if s:flag == 1
		exec "make -C " . vdir
		exec "cw"
	endif
	unlet s:flag
	unlet vdir
endfunc
map <S-F5> :call DoMake()<cr>
autocmd filetype go map <F9> :w<cr>:!go run %<cr>
autocmd filetype rust map <F9> :w<cr>:!rustc % -g<cr>
autocmd filetype python map <F9> :w<cr>:!python2 %<cr>
autocmd filetype python map <S-F9> :w<cr>:!python3 %<cr>
autocmd filetype javascript map <F9> :w<cr>:!node %<cr>
autocmd filetype c map <F9> :w<cr>:!gcc % -o %< -g -Wall -lpthread<cr>
autocmd filetype cpp map <F9> :w<cr>:!g++ % -o %< -g -std=c++14 -Wall -I. -lpthread -mcmodel=large -ljsoncpp -lgmpxx -lgmp -lncurses -lglut -lGL -lGLU -lrdmacm -libverbs -lrt<cr>
autocmd filetype cpp map <S-F9> :w<cr>:!g++ % -o %< -g -std=c++17 -Wall -lstdc++fs<cr>
autocmd filetype tex map <F9> :w<cr>:!xelatex %<cr>
autocmd filetype java map <F9> :w<cr>:!javac %<cr>
autocmd filetype scala map <F9> :w<cr>:!scalac %<cr>
autocmd filetype haskell map <F9> :w<cr>:!runhaskell %<cr>
map <F5> :split %<.in<cr>
map <F6> :split %<.out<cr>
map <F7> :!gdb %< -tu<cr>
"map <C-F9> :!time ./%< < %<.in<cr>
map <C-F9> :!time ./%< <cr>
autocmd filetype tex map <C-F9> :!okular %<.pdf<cr>
autocmd filetype java map <C-F9> :!java %< <cr>
autocmd filetype scala map <C-F9> :!scala %< <cr>
autocmd filetype haskell map <C-F9> :!runhaskell %< <cr>
autocmd filetype rust map == :FormatLines <cr>
autocmd filetype rust vnoremap = :'<,'>FormatLines <cr>
autocmd filetype cpp,cuda map == :FormatLines <cr>
autocmd filetype cpp,cuda vnoremap = :'<,'>FormatLines <cr>
autocmd filetype haskell map == :FormatLines <cr>
autocmd filetype haskell vnoremap = :'<,'>FormatLines <cr>

" Multi panel
if !has("nvim")
	for i in range(char2nr('a'), char2nr('z'))
		let i = nr2char(i)
		exec "set <M-".i.">=\<Esc>".i
		exec "inoremap \<Esc>".i." <M-".i.">"
	endfor
endif

" move focus
nnoremap <cr> <C-w>w
" change layout
nnoremap <M-r> <C-w>r
nnoremap <M-j> <C-w>J
nnoremap <M-k> <C-w>K
nnoremap <M-l> <C-w>L
nnoremap <M-h> <C-w>H

" Duplicate default register to system clipboard register
map <F8> :let @+=@" <cr>

" lshift hurts my little finger
map <leader><leader> :w<cr>

" Search result centered
noremap <silent> n nzz
noremap <silent> N Nzz
noremap <silent> * *zz
noremap <silent> # #zz
noremap <silent> g* g*zz

" Disable arrow keys
noremap <Up> <nop>
noremap <Down> <nop>
noremap <Left> <nop>
noremap <Right> <nop>

" xmonad-style shortcut
noremap <silent> <C-h> :vertical resize -7<cr>
noremap <silent> <C-l> :vertical resize +7<cr>
nnoremap <C-j> <C-w>w
nnoremap <C-k> <C-w>W

""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" NERDTree
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
let NERDTreeMinimalUI=1


"""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Config Colorscheme, Enable truecolor support
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""
set background=light
let g:one_allow_italics = 1
"colorscheme one
let g:gruvbox_contrast_dark='soft'
let g:gruvbox_contrast_light='soft'
colorscheme gruvbox
"colorscheme desert
"hi! Normal ctermbg=NONE guibg=NONE
"map <S-F12> :set background=dark<cr>

"Credit joshdick
"Use 24-bit (true-color) mode in Vim/Neovim when outside tmux.
"If you're using tmux version 2.2 or later, you can remove the outermost $TMUX check and use tmux's 24-bit color support
"(see < http://sunaku.github.io/tmux-24bit-color.html#usage > for more information.)
function! EnableTrueColor()
	if ($TERM != 'linux')
		if (has("nvim"))
			"For Neovim 0.1.3 and 0.1.4 < https://github.com/neovim/neovim/pull/2198 >
			let $NVIM_TUI_ENABLE_TRUE_COLOR=1
		endif
		"For Neovim > 0.1.5 and Vim > patch 7.4.1799 < https://github.com/vim/vim/commit/61be73bb0f965a895bfb064ea3e55476ac175162 >
		"Based on Vim patch 7.4.1770 (`guicolors` option) < https://github.com/vim/vim/commit/8a633e3427b47286869aa4b96f2bfc1fe65b25cd >
		" < https://github.com/neovim/neovim/wiki/Following-HEAD#20160511 >
		if (has("termguicolors"))
			set t_8f=[38;2;%lu;%lu;%lum
			set t_8b=[48;2;%lu;%lu;%lum
			set termguicolors
		endif
	endif
endfunction

call EnableTrueColor()

map <S-F12> :call ToggleTransparent()<cr>

function! SetTermGuiColors()
	if (has("termguicolors"))
		set termguicolors
	endif
endfunction

function! SetNoTermGuiColors()
	if (has("termguicolors"))
		set notermguicolors
	endif
endfunction

let g:is_transparent = 0

function! ToggleTransparent()
	if g:is_transparent
		set background=light
		call SetTermGuiColors()
		let g:is_transparent = 0
	else
		set background=dark
		hi! Normal ctermbg=NONE guibg=NONE
		"call SetNoTermGuiColors()
		let g:is_transparent = 1
	endif
endfunction

if exists('$TMUX')
	call ToggleTransparent()
endif


"""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Airline
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""
let g:airline_theme='one'
let g:airline#extensions#tabline#enabled = 1


"""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Python Syntax
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""
let g:python_highlight_all = 1
let g:python_version_2 = 1
let g:python_highlight_file_headers_as_comments = 1


"""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" cpp enhanced highlight
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""
let g:cpp_class_scope_highlight = 1
let g:cpp_member_variable_highlight = 1
let g:cpp_class_decl_highlight = 1


"""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" linux coding style
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""
"let g:linuxsty_patterns = [ "/home/cjr/Developing/c-data-structure" ]


"""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" AsyncRun
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""
let g:asyncrun_open = 6
let g:asyncrun_bell = 1
nnoremap <F10> :call asyncrun#quickfix_toggle(6)<cr>


"""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" LeaderF
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""
let g:Lf_ShortcutF = '<C-p>'
let g:Lf_ShortcutB = '<M-n>'
noremap <C-n> :LeaderfMru<cr>
noremap <M-p> :LeaderfFunction<cr>
noremap <M-n> :LeaderfBuffer<cr>
noremap <M-m> :LeaderfTag<cr>
let g:Lf_StlSeparator = { 'left': '', 'right': '', 'font': '' }

let g:Lf_RootMarkers = ['.project', '.root', '.svn', '.git']
let g:Lf_WorkingDirectoryMode = 'Ac'
let g:Lf_WindowHeight = 0.30
let g:Lf_CacheDirectory = expand('~/.vim/cache')
let g:Lf_ShowRelativePath = 0
let g:Lf_HideHelp = 1
let g:Lf_StlColorscheme = 'powerline'
let g:Lf_PreviewResult = {'Function':0}

let g:Lf_NormalMap = {
	\ "File":   [["<ESC>", ':exec g:Lf_py "fileExplManager.quit()"<CR>']],
	\ "Buffer": [["<ESC>", ':exec g:Lf_py "bufExplManager.quit()"<CR>']],
	\ "Mru":    [["<ESC>", ':exec g:Lf_py "mruExplManager.quit()"<CR>']],
	\ "Tag":    [["<ESC>", ':exec g:Lf_py "tagExplManager.quit()"<CR>']],
	\ "Function":    [["<ESC>", ':exec g:Lf_py "functionExplManager.quit()"<CR>']],
	\ "Colorscheme":    [["<ESC>", ':exec g:Lf_py "colorschemeExplManager.quit()"<CR>']],
	\ }


"""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Haskell-vim
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" vim-hindent
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""
let g:hindent_on_save = 0
let g:hindent_indent_size = 4
let g:hindent_line_length = 100
let g:hindent_command = "/usr/bin/hindent"

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" codefmt
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""
let s:plugin = maktaba#plugin#Get('codefmt')
call s:plugin.Flag('hindent_indent_size', '4')
call s:plugin.Flag('hindent_line_length', '100')
call s:plugin.Flag('brittany_indent', '4')
call s:plugin.Flag('brittany_columns', '100')

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" Highlightedyank
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""
let g:highlightedyank_highlight_duration = 250
if !exists('##TextYankPost')
	map y <Plug>(highlightedyank)
endif
" hi! HighlightedyankRegion cterm=reverse gui=reverse

"""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" CoC
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""
function! SetupCoc() abort
	let g:coc_global_extensions = [ 'coc-rust-analyzer', 'coc-clangd', 'coc-highlight' ]

	" Having longer updatetime (default is 4000 ms = 4 s) leads to noticeable
	" delays and poor user experience.
	set updatetime=300

	" Use tab for trigger completion with characters ahead and navigate.
	" NOTE: Use command ':verbose imap <tab>' to make sure tab is not mapped by
	" other plugin before putting this into your config.
	inoremap <silent><expr> <TAB>
		\ pumvisible() ? "\<C-n>" :
		\ <SID>check_back_space() ? "\<TAB>" :
		\ coc#refresh()
	inoremap <expr><S-TAB> pumvisible() ? "\<C-p>" : "\<C-h>"

	function! s:check_back_space() abort
		let col = col('.') - 1
		return !col || getline('.')[col - 1] =~# '\s'
	endfunction

	" Use <c-space> to trigger completion.
	inoremap <silent><expr> <c-space> coc#refresh()

	" Use <cr> to confirm completion, `<C-g>u` means break undo chain at current
	" position. Coc only does snippet and additional edit on confirm.
	if exists('*complete_info')
		" inoremap <expr> <cr> complete_info()["selected"] != "-1" ? "\<C-y>" : "\<C-g>u\<CR>"
		" Use Enter to choose the first item in the popup menu
		inoremap <expr> <cr> complete_info()["selected"] != "-1" ? "\<C-y>" :
		    \ pumvisible() ? "\<C-y>" :
		    \ <SID>check_back_space() ? "\<CR>" :
		    \ "\<C-g>u\<CR>"
	els
		imap <expr> <cr> pumvisible() ? "\<C-y>" : "\<C-g>u\<CR>"
	endif

	" Use <leader>j and <leader>k to navigate diagnostics
	nmap <silent> <leader>j <Plug>(coc-diagnostic-next)
	nmap <silent> <leader>k <Plug>(coc-diagnostic-prev)

	" GoTo code navigation.
	nmap <silent> gd <Plug>(coc-definition)
	nmap <silent> gs :sp<CR><Plug>(coc-definition)
	nmap <silent> gv :vsp<CR><Plug>(coc-definition)
	nmap <silent> gy <Plug>(coc-type-definition)
	nmap <silent> gi <Plug>(coc-implementation)
	nmap <silent> gr <Plug>(coc-references)

	" Use K to show documentation in preview window.
	noremap <silent> K :call <SID>show_documentation()<CR>
	"vnoremap <silent> K :call <SID>show_documentation()<CR>

	function! s:show_documentation()
		if (index(['vim','help'], &filetype) >= 0)
			execute 'h '.expand('<cword>')
		else
			call CocAction('doHover')
		endif
	endfunction

	function! Highlight() abort
		call CocActionAsync('highlight')
	endfunction

	" Highlight the symbol and its references when holding the cursor.
	augroup CursorHoldHighlight
		autocmd!
		autocmd CursorHold * call Highlight()
	augroup END

	" Remap for rename current word
	nmap <leader>rn <Plug>(coc-rename)

	" Formatting selected code.
	xmap <leader>f <Plug>(coc-format-selected)
	nmap <leader>f <Plug>(coc-format-selected)
endfunction

" This below prevents diagnostic style disappearing after switching
" colorscheme
function! CocHighlights() abort
	highlight link CocErrorSign GruvboxRed
	highlight link CocWarningSign GruvboxYello
	highlight link CocInfoSign GruvboxBlue
	highlight link CocHintSign GruvboxGreen
	highlight CocUnderline cterm=underline gui=underline
	highlight CocHighlightText term=bold,reverse cterm=bold ctermfg=0 ctermbg=121 gui=bold guifg=bg guibg=LightGreen
	" use highlight! to overwrite any default
	highlight! link CocErrorHighlight CocUnderline
	highlight! link CocWarningHighlight CocUnderline
	highlight! link CocInfoHighlight CocUnderline
	highlight! link CocHintHighlight CocUnderline
	highlight! link CocFloating Pmenu
endfunction

augroup CocHighlights
	autocmd!
	autocmd ColorScheme * call CocHighlights()
augroup END
call CocHighlights()

if has_key(plugs, "coc.nvim")
	call SetupCoc()
endif


"""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" caenrique / nvim-maximize-window-toggle
"""""""""""""""""""""""""""""""""""""""""""""""""""""""""
" ToggleOnly
""
" @public
" Toggles between the current window and the current buffer
" opened in a new tab page.
""
function! ToggleOnly()
	if winnr("$") > 1
	" There are more than one window in this tab
		if exists("b:maximized_window_id")
			call win_gotoid(b:maximized_window_id)
		else
			let b:origin_window_id = win_getid()
			tab sp
			let b:maximized_window_id = win_getid()
		endif
	else
	" This is the only window in this tab
		if exists("b:origin_window_id")
			let l:origin_window_id = b:origin_window_id
			tabclose
			call win_gotoid(l:origin_window_id)
			unlet b:maximized_window_id
			unlet b:origin_window_id
		endif
	endif
endfunction

""
" Maximize the current buffer as a toggle
""
command! ToggleOnly call ToggleOnly()
nnoremap <leader>z :ToggleOnly<cr>
