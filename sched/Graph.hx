package sched;

class Graph extends flash.display.Sprite {

   public static var g(getGraph, null): Graph;

   static function getGraph() {
      if (g == null)
         g = new Graph();

      return g;
   }

   function new() {
      super();
   }

   static var res = 5.0;

   public function addPoint(t: Float, y: Float, cidx: Int) {
      var col : UInt = cols[cidx];

      graphics.lineStyle(1, col);
      graphics.drawCircle(t / res, y, 1);
   }

   public function addLine() {
      graphics.lineStyle(1, 0x000000);
      var x = flash.Lib.getTimer() / res;
      graphics.moveTo(x, 0);
      graphics.lineTo(x, 480);
   }

   public static var G_SWITCHES = 0;
   public static var G_TMR_SPATE = 1;
   public static var G_OVERHEAD = 2;
   public static var G_TARGET_DELTA = 3;
   public static var G_PCOUNT = 4;
   public static var G_SPAWNED = 5;


   static var cols = [
      0xff0000,
      0x00ff00,
      0x0000ff,
      0xff8800,
      0xff00ff,
      0x000000,
      ];

}
