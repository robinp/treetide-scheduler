import com.treetide.sched.Sched;

class Test2 {

   static var anims = 1;
   static var loopsize = 10000;
   
   static function test_start() { 
      var c_pid = M.m.spawn(Test2, child_start, [M.m.getMyPid()], "child");
      M.m.msg(c_pid, "alma");
      M.m.msg(c_pid, "korte");
      M.m.msg(c_pid, "csirke");
      M.m.msg(c_pid, "tyuk");
      
      return M.m.recv(parent_recv);
   }

   static function parent_recv() {
      trace("received back: " + M.m.peek());

      return if (M.m.peek() == "tyuk") {
         trace("tyuk!!");
         //M.m.terminate();
         throw new flash.errors.Error("tyuk");
      }
      else M.m.recv(parent_recv);
   }

   static function child_start(p_pid: PidT) {
      return M.m.recv(child_recv, [p_pid]);
   }

   static function child_recv(p_pid: PidT) {
      var m = M.m.peek();
      return switch (m) {
         case "alma": 
            trace("nem szeretem az almat");
            M.m.refuse();

         default:
            trace("ezt szeretem: " + m);
            M.m.msg(p_pid, m);
            M.m.recv(child_recv, [p_pid]);
      }

   }
   
   static function main() {

      M.m.setTrace();
      M.m.setFps(Std.int(flash.Lib.current.stage.frameRate));

      trace("loopsize: " + loopsize);
      SimpleAnim.start(anims);
  
      #if IGRAPH
      flash.Lib.current.addChild(Graph.g);
      #end

      M.m.spawn(Test2, test_start);
      M.m.start();

   }
}
