(*
 * Copyright (C) 2015 BeSport, Julien Sagot
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, with linking exception;
 * either version 2.1 of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.
*)

(* Warning: Tsv file need to end with '\r' *)
{
type i18n_expr =
  | Var of string                    (* This is a string *)
  | Str of string                    (* {{ user }} *)
  | Cond of string * string * string (* {{{ many ? s || }}} *)

let flush buffer acc =
  let acc = match String.escaped (Buffer.contents buffer) with
    | "" -> acc
    | x -> Str x :: acc in
  Buffer.clear buffer
; acc

}

let lower = ['a'-'z']
let upper = ['A'-'Z']
let num = ['0'-'9']

let id = (lower | ['_']) (lower | upper | num | ['_'])*

rule parse_lines langs acc = parse
  | (id as key) '\t' {
      (* FIXME: Will break if List.map change its order of execution *)
      let tr = List.map (fun lang ->
          (lang, parse_expr (Buffer.create 0) [] lexbuf) ) langs in
    eol langs ((key, tr) :: acc) lexbuf }
  | eof { List.rev acc }

and eol langs acc = parse
  | [^'\n']* "\n" { Lexing.new_line lexbuf
                  ; parse_lines langs acc lexbuf}
  | eof { List.rev acc }

and parse_expr buffer acc = parse

  | "{{{" ' '* (id as c) ' '* "?" {
    let s1 = parse_string_1 (Buffer.create 0) lexbuf in
    let s2 = parse_string_2 (Buffer.create 0) lexbuf in
    let acc = flush buffer acc in
    parse_expr buffer (Cond (c, s1, s2) :: acc) lexbuf
  }

  | "{{" " "* (id as x) " "* "}}" {
      let acc = flush buffer acc in
      parse_expr buffer (Var x :: acc) lexbuf }

  | ['\n' '\t'] as c {
    if c = '\n' then Lexing.new_line lexbuf ;
    let acc = flush buffer acc in List.rev acc }

  | [^ '\n' '\t'] as c { Buffer.add_char buffer c
                       ; parse_expr buffer acc lexbuf }

and parse_string_1 buffer = parse
  | "||" { String.escaped (Buffer.contents buffer) }
  | _ as c { Buffer.add_char buffer c
           ; parse_string_1 buffer lexbuf }

and parse_string_2 buffer = parse
  | "}}}" { String.escaped (Buffer.contents buffer) }
  | _ as c { Buffer.add_char buffer c
           ; parse_string_2 buffer lexbuf }

{

let print_header fmt default_lang =
  Format.pp_print_string fmt @@
  "let%server language =\n\
   Eliom_reference.Volatile.eref \
   ~scope:Eliom_common.request_scope " ^ default_lang ^ "\n\
   \n\
   let%server get_lang () = Eliom_reference.Volatile.get language\n\
   \n\
   (* For non connected users, \
   we record the language in a session reference: *)\n\
   let%server non_connected_language =\n\
   Eliom_reference.Volatile.eref ~scope:Eliom_common.default_session_scope\n\
   (if true then None else Some " ^ default_lang ^ ")\n\
   \n\
   let%client language = ref " ^ default_lang ^ "\n\
   let%client non_connected_language =\n\
   ref (if true then None else Some " ^ default_lang ^ ")\n\
   \n\
   let%client get_lang () = !language\n\
   \n\
   [%%shared\n\
   [@@@ocaml.warning \"-27\"]\n\
   let pcdata = Eliom_content.Html.F.pcdata\n\
"

let print_footer fmt = Format.pp_print_string fmt "]\n"

type arg = M of string | O of string

let print_module_body print_expr =
  let args langs =
    let rec f a =
      function [] -> List.rev a
             | Var x :: t          -> f (M x :: a) t
             | Cond (x, _, _) :: t -> f (O x :: a) t
             | _ :: t              -> f a t in
    List.map (f []) langs
    |> List.flatten
    |> List.sort_uniq compare in
  let print_args fmt args =
    Format.pp_print_list
      ~pp_sep:(fun fmt () -> Format.pp_print_char fmt ' ')
      (fun fmt -> function
         | M x -> Format.fprintf fmt "~%s" x
         | O x -> Format.fprintf fmt "?(%s=false)" x) fmt args in
  Format.pp_print_list
    ~pp_sep:(fun fmt () -> Format.pp_print_string fmt "\n")
    (fun fmt (key, tr) ->
       let args = args (List.map snd tr) in
       Format.fprintf fmt "let %s ?(lang = get_lang ()) () =\n\
                           match lang with\n%a"
         key
         (Format.pp_print_list
            ~pp_sep:(fun fmt () -> Format.pp_print_string fmt "\n")
            (fun fmt (lang, tr) ->
               Format.fprintf fmt "| %s -> (fun %a () -> %a)"
                 lang print_args args print_expr tr) ) tr )

let print_expr_html =
  Format.pp_print_list
    ~pp_sep:(fun fmt () -> Format.pp_print_string fmt "@")
    (fun fmt -> function
       | Str s -> Format.fprintf fmt "[pcdata \"%s\"]" s
       | Var v -> Format.pp_print_string fmt v
       | Cond (c, s1, s2) ->
         Format.fprintf fmt "[pcdata (if %s then \"%s\" else \"%s\")]"
           c s1 s2)

let print_expr_string =
  Format.pp_print_list
    ~pp_sep:(fun fmt () -> Format.pp_print_string fmt "^")
    (fun fmt -> function
       | Str s -> Format.fprintf fmt "\"%s\"" s
       | Var v -> Format.pp_print_string fmt v
       | Cond (c, s1, s2) ->
         Format.fprintf fmt "(if %s then \"%s\" else \"%s\")"
           c s1 s2)

let input_file = ref "-"
let output_file = ref "-"
let langs = ref ""
let default_lang = ref ""

let options = Arg.align
    [ ( "--langs", Arg.Set_string langs
      , " Comma-separated langs (from ocaml sum type) (e.g. Us,Fr). \
         Must be ordered as in source TSV file.")
    ; ( "--default-lang", Arg.Set_string default_lang
      , " Set the default lang.")
    ; ( "--input-file", Arg.Set_string input_file
      , " TSV file containing keys and translations. \
         If option is omited or set to -, read on stdin.")
    ; ( "--ouput-file", Arg.Set_string output_file
      , " File TSV file containing keys and translations. \
         If option is omited or set to -, write on stdout.") ]

let usage = "usage: ocsigen-i18n-generator [options] [< input] [> output]"

let _ = Arg.parse options (fun s -> ()) usage

let _ =
  let in_chan =
    match !input_file with
    | "-" -> stdin
    | file -> open_in file in
  let out_chan =
    match !output_file with
    | "-" -> stdout
    | file -> open_out file in
  let langs = Str.split (Str.regexp ",") !langs in
  let default_lang = !default_lang in
  assert (List.mem default_lang langs) ;
  let lexbuf = Lexing.from_channel in_chan in
  (try let key_values = parse_lines langs [] lexbuf in
     let output = Format.formatter_of_out_channel out_chan in
     print_header output default_lang ;
     Format.fprintf output "module Tr = struct\n" ;
     print_module_body print_expr_html output key_values ;
     Format.fprintf output "\nmodule S = struct\n" ;
     print_module_body print_expr_string output key_values ;
     Format.fprintf output "\nend\n" ;
     Format.fprintf output "end\n" ;
     print_footer output
   with Failure msg ->
     failwith (Printf.sprintf "line: %d" lexbuf.lex_curr_p.pos_lnum) ) ;
  close_in in_chan ;
  close_out out_chan
}
