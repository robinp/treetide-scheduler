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

package com.treetide.sched.lib;

import com.treetide.sched.Sched;

enum CollectorMsg {
   CM_Folded(res: Dynamic, custom: Dynamic);
}

class Collector {

   public static function fold<A,X>(
         ret_to: PidT,
         count: UInt,
         fold_base: A,
         fold_fun: A -> X -> A,
         ?custom: Dynamic ) {

      return function() {
         var res = fold_base;

         var loop = function(i: UInt) {
            res = fold_fun(res, M.m.peek());

            ++i;
            if (i == count) {
               M.m.msg(ret_to, CM_Folded(res, custom));
            }
            else {
               M.m.recv(null, null, [i]);
            }
         }

         M.m.recv(loop, [0]);
      }
   }

   public static function collect<X>(
         ret_to: PidT,
         count: UInt,
         ?custom: Dynamic ) {

      return fold(
            ret_to, 
            count,
            new List<X>(), function (acc: List<X>, e: X) {
               acc.add(e);
               return acc;
            },
            custom );
   }


}
