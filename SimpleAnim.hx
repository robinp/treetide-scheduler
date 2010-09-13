import Sched;

class SimpleAnim extends flash.display.Sprite{

   public static function start(n: Int) { 
      for (i in 0...n) {
         var a = new SimpleAnim();
         flash.Lib.current.addChild(a);
         a.x = Std.random(640);
         a.y = Std.random(480);

         M.m.spawn(a, a.run);
      }
   }

   public function new() {
      super();
      r = 20 + Math.random() * 40;
      spd = 1.0;
      rot = 0.0;
      col = Std.random(0xffffff);
      last_t = 0;
   }

   public function run() {
      var t = M.m.getFrameT();
      var dt = t - last_t; 
      last_t = t;

      rot += spd * dt / 1000.0;
      var x = Math.cos(rot);
      var y = Math.sin(rot);

      graphics.clear();
      graphics.beginFill(col);
      graphics.drawCircle(r*x, r*y, 20);

      return M.m.sleep(0, run);
   }

   var r: Float;
   var spd: Float;
   var col: UInt;

   var rot: Float;
   var last_t: Int;
}

