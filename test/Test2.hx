import com.treetide.sched.Sched;

class Test2 {

   static var anims = 10;
   
   static function test_start() { 
      var c_pid = M.m.spawn(Test2, child_start, [M.m.pid()], "child");
      M.m.msg(c_pid, "apple");
      M.m.msg(c_pid, "pear");
      M.m.msg(c_pid, "chicken");
      M.m.msg(c_pid, "hen");
      
      return M.m.recv(parent_recv);
   }

   static function parent_recv() {
      trace("received back: " + M.m.peek());

      if (M.m.peek() == "hen") {
         trace("hen :>.");
      }
      
      M.m.recv();
   }

   static function child_start(p_pid: PidT) {
      return M.m.recv(child_recv, [p_pid]);
   }

   static function child_recv(p_pid: PidT) {
      var m = M.m.peek();
      return switch (m) {
         case "apple": 
            trace("i don't like apples");
            M.m.refuse();

         default:
            trace("i do like: " + m);
            M.m.msg(p_pid, m);

            if (m == "hen") {

               trace("spawning collection receiver");

               var p = M.m.spawn(null, function () {
                  if (M.m.peek() != null) {
                     trace("got: " + M.m.peek());
                  }
                  
                  trace("waiting for more");
                  M.m.recv();
               });

               trace("spawning collectors");

               var cp = M.m.spawn(null, com.treetide.sched.lib.Collector.collect(
                        p, 10, "collected"));

               var fp = M.m.spawn(null, com.treetide.sched.lib.Collector.fold(
                        p, 10, "", function(acc: String, e: Int) {
                           return acc + e + ":";
                        }, "folded"));

               trace("messaging collectors");

               for (i in 0...10) {
                  M.m.msg(cp, i);
                  M.m.msg(fp, i);
               }
            }

            M.m.recv(child_recv, [p_pid]);
      }

   }
   
   static function main() {

      M.m.setTrace();
      M.m.setFps(Std.int(flash.Lib.current.stage.frameRate));

      SimpleAnim.start(anims);
  
      M.m.spawn(Test2, test_start);
      M.m.start();
   }
}
