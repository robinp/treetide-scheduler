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


   // ----- test controller -----

   static var anims = 10;

   static var loopsize = 10000;
   static var t0: Int;
   static var t1: Int;
   static var testname: String;
 
   static function test_show_result(next_test: Void -> Void) {
      // until no messages, this hack is required

      if (M.m.getProcCount() != 1 + anims) 
         return M.m.yield(test_show_result, [next_test]);

      t1 = T(); trace(testname + ": " + (t1 - t0));

      #if IGRAPH
      Graph.g.addLine();
      #end 

      return M.m.yield(next_test);

   }

   static function test_spawner(
         tname: String, 
         tfun: Dynamic, 
         ?targs: Array<Dynamic>) {

      testname = tname;

      for (i in 0...loopsize)
         M.m.spawn(Test, tfun, targs);

      t0 = T(); 
   }

   static function test_start() { 
      test_spawner("********** dummy loop", dummy);
      M.m.yield(test_show_result, [test_simple_add]);
   }
 
   static function test_simple_add() { 
      test_spawner("simple_add loop", simple_add);
      M.m.yield(test_show_result, [test_fact2]);
   }
 
   static function test_fact2() { 
      test_spawner("fact2 loop", fact2, [10, 1]);
      M.m.yield(test_show_result, [test_fact3]);
   }
  
   static function test_fact3() { 
      test_spawner("fact3 loop", fact3, [10, 1]);
      M.m.yield(test_show_result, 
            [test_start]
            //[test_finish]
      );
   }

   static function test_finish() {
      trace("testing finished");
   }

   static function main() {

      M.m.setTrace();
      M.m.setFps(Std.int(flash.Lib.current.stage.frameRate));

      trace("loopsize: " + loopsize);

      for (i in 0...anims) {
         var a = new SimpleAnim();
         flash.Lib.current.addChild(a);
         a.x = Std.random(640);
         a.y = Std.random(480);

         M.m.spawn(a, a.run);
      }

      #if IGRAPH
      flash.Lib.current.addChild(Graph.g);
      #end

      M.m.spawn(Test, test_start);
      M.m.start();


   }
}
