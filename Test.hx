import Sched;

class A {
   public function new() {
      b = 33;
   }

   public static function trace_a1() {
      trace("a1");
   }

   public function trace_a2() {
      trace("a2");
      trace("b: " + b);
      trace("this: " + this);
   }

   var b: Int;
}

class Test {

   static var T = 
          #if flash9 flash.Lib.getTimer 
          #else function () {return Std.int(neko.Sys.cpuTime()*1000);}
          #end ;


   static function trace_x() {
      trace("x");
   }

   static function dummy() {
      // no action
   }

   static function simple_add() {
      var a = 4;
      var b = 5;
      var x = a + b;
   }

   static function fact(n: Int, result: Int) {
      if (n == 0 || n == 1) {
         //trace("result: " + result);
      }
      else {
         M.m.spawn(Test, function() fact(n-1, result*n));
      }
   }
 
   static function fact2(n: Int, result: Int) {
      if (n == 0 || n == 1) {
         //trace("result: " + result);
      }
      else {
         M.m.spawn(Test, fact2, [n-1, result*n]);
      }
   } 
 
   static function fact3(n: Int, result: Int) {
      if (n == 0 || n == 1) {
         //trace("result: " + result);
      }
      else {
         M.m.yield(fact3, [n-1, result*n]);
      }
   }


   static function main() {
      M.m.setTrace();

      var t0: Int, t1: Int;
      var testname: String;

      var loopsize = 100;

      var a = new A();
      Reflect.callMethod(null, trace_x, null);
      Reflect.callMethod(null, A.trace_a1, null);
      Reflect.callMethod(null, a.trace_a2, null);

      trace("loopsize: " + loopsize);

      // ---

      testname = "dummy loop";

      for (i in 0...loopsize)
         M.m.spawn(Test, dummy);

      t0 = T(); M.m.start();
      t1 = T(); trace(testname + ": " + (t1 - t0));
      
      // --- 
      
      testname = "simple_add loop";

      for (i in 0...loopsize)
         M.m.spawn(Test, simple_add);

      t0 = T(); M.m.start();
      t1 = T(); trace(testname + ": " + (t1 - t0));

      // ---

      testname = "fact loop";

      for (i in 0...loopsize)
         M.m.spawn(Test, function() fact(10, 1));
      
      t0 = T(); M.m.start();
      t1 = T(); trace(testname + ": " + (t1 - t0)); 
 
      // ---

      testname = "fact2 loop";

      for (i in 0...loopsize)
         M.m.spawn(Test, fact2, [10, 1]);
      
      t0 = T(); M.m.start();
      t1 = T(); trace(testname + ": " + (t1 - t0));
 
      // ---

      testname = "fact3 loop";

      for (i in 0...loopsize)
         M.m.spawn(Test, fact3, [10, 1]);
      
      t0 = T(); M.m.start();
      t1 = T(); trace(testname + ": " + (t1 - t0));

   }
}
