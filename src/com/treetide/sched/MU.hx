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
