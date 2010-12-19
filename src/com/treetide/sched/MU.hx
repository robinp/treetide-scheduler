/*
   Copyright (c) 2010, the haXe Project Contributors
   All rights reserved.

   Redistribution and use in source and binary forms, with or without
   modification, are permitted provided that the following conditions are met:

      * Redistributions of source code must retain the above copyright
        notice, this list of conditions and the following disclaimer.

      * Redistributions in binary form must reproduce the above copyright
        notice, this list of conditions and the following disclaimer in the
        documentation and/or other materials provided with the distribution.

   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
   ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
   WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
   DISCLAIMED. IN NO EVENT SHALL THE HAXE PROJECT CONTRIBUTORS BE LIABLE FOR ANY
   DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
   (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
   LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
   ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
   (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
   SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

package com.treetide.sched;

import com.treetide.sched.Sched;

class MU {

   inline public static function msg(pid: PidT, m: Dynamic) {
      M.m.msg(pid, m);
   }

   inline public static function getD(reference: Int): PidT {
      return M.m.getD(reference);
   } 
 
   inline public static function getUserT(): Int {
      return M.m.getUserT();
   }

   inline public static function spawn(cobj: Dynamic, cont: ContT, ?args: Array<Dynamic>, ?name: String) {
      return M.m.spawn(cobj, cont, args, name);
   }

   inline public static function yield(?cont: ContT, ?cargs: Array<Dynamic>) {
      M.m.yield(cont, cargs);
   }

   inline public static function recv(
         ?timeout: Int, 
         ?cont: ContT, ?cargs: Array<Dynamic>, 
         ?to_cont: ContT) {

      M.m.recv(timeout, cont, cargs, to_cont);
   }
   
   inline public static function peek() {
      return M.m.peek();
   }

   inline public static function pid(): PidT {
      return M.m.pid();
   }


}
