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
