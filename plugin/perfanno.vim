if exists('g:loaded_perfanno')
    finish
endif

let s:save_cpo = &cpo
set cpo&vim

command! PerfAnnoLoadData lua require("perfanno.load_data").load_data()
command! PerfAnnoDebugPrint lua require("perfanno.load_data").debug_print(PerfAnnotations)
command! PerfAnnoAnnotateBuffer lua require("perfanno.show_annotations").annotate_buffer()
command! PerfAnnoClearBuffer lua require("perfanno.show_annotations").clear_buffer()

let &cpo = s:save_cpo
unlet s:save_cpo

let g:loaded_perfanno = 1
