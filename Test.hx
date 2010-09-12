import Sched;

class Test {

   static var T = 
          #if flash9 flash.Lib.getTimer 
          #else function () {return Std.int(neko.Sys.cpuTime()*1000);}
          #end ;


   static function dummy() {
      // no action
   }

   static function simple_add() {
      var a = 4;
      var b = 5;
      var x = a + b;
   }

   static function main() {
      M.m.setTrace();

      var t0: Int, t1: Int;
      var testname: String;

      var loopsize = 10000;

      trace("loopsize: " + loopsize);

      for (i in 0...loopsize)
         M.m.spawn(dummy);

      testname = "dummy loop";
      t0 = T(); M.m.start();
      t1 = T(); trace(testname + ": " + (t1 - t0));
      
      for (i in 0...loopsize)
         M.m.spawn(simple_add);

      testname = "simple_add loop";
      t0 = T(); M.m.start();
      t1 = T(); trace(testname + ": " + (t1 - t0));
   }
}
