// Defines:
//
// NDEBUG - turn off assertions
// ISTAT - turn on internal statistics collection
// POOL_MAX - turn on maximum process number checking
// DEBUG_TRACES - turn on debug traces

#if flash
import flash.Lib;
import flash.events.Event;
#end

enum PState {
   PNew;
   PRun;
   PSleep;
}

typedef ContT = Dynamic;

typedef PidT = Int;

typedef ProcEntry = {
   // process state
   var state: PState;
   
   // continuation function to call next
   // and its arguments
   var cobj: Dynamic;
   var cont: ContT;
   var cargs: Array<Dynamic>;

   // optional name of the process (??? mapped opt)
   var name: String;

   // high 16 bit of pid (index-reuse counter)
   var hpid: Int;

   // timer variable, used depending on state
   //
   // PSleep: 
   //    The wake-up time. Will be woken if the 
   //    current frame_start >= timer.
   //    
   var timer: Int;

   // TODO:
   // wait for message
   // waiting for pids, etc
}

class M {
   public static var m(getM, null): M;

   static function getM(): M {
      if (m == null)
         m = new M();
      return m;
   }

   function new() {
      pool = new Array();
      active_lpids = new CGList<Int>(-1);
      free_lpids = new List();
      
      last_f_start = 0;
      act_f_start = 0;

      setFps(30);
      
      proc_num = 0;
   }

   inline function updateTargetDelta() {
      target_frame_delta = ideal_frame_delta - render_overhead;
   }

   public function setFps(fps: Int) {
      ideal_frame_delta = Std.int(1000 / fps);

      // initial guess
      render_overhead = 5;

      updateTargetDelta();
   }

   inline function emptyEntry(cobj: Dynamic, f: ContT, args: Array<Dynamic>, name: String) {
      return {state: PNew, cobj: cobj, cont: f, cargs: args, name: name, hpid: 0, timer: 0};
   }

   inline function resetEntry(e: ProcEntry, cobj: Dynamic, f: ContT, args: Array<Dynamic>, name: String) {
      e.state = PNew;
      e.cobj = cobj;
      e.cont = f;
      e.cargs = args;
      e.name = name;
      // e.timer is not valid in PNew so not reset

      e.hpid++;
      if (e.hpid == 0x7FFF) {
         // turn it around
         e.hpid = 0;
      }
   }

   function newLPid(cobj: Dynamic, f: ContT, args: Array<Dynamic>, name: String): Int {
      var new_lpid = if (free_lpids.isEmpty()) {
         // we have to extend the pool
         #if POOL_MAX
         if (proc_pool.length == MAX_PROC) {
            throw "! Maximum number of processes reached (" + MAX_PROC + ")";
         }
         #end

         pool.push(emptyEntry(cobj, f, args, name));
         pool.length - 1;
      }
      else {
         var lpid = free_lpids.pop();
         resetEntry(pool[lpid], cobj, f, args, name);
         lpid;
      };

      active_lpids.spawn(new_lpid); 
      proc_num++;

      return new_lpid;
   }

   inline function fullPid(hpid: Int, lpid: Int) {
      #if !NDEBUG
      if ((lpid & 0xFFFF) != lpid) 
         throw "! LPID must be <= 0xFFFF";
      #end
      return (hpid << 16) | lpid;
   }

   public function spawn(cobj: Dynamic, cont: ContT, ?args: Array<Dynamic>, ?name: String): PidT {
      if (args == null) {
         args = [];
      }

      var lpid = newLPid(cobj, cont, args, name);
      var p = pool[lpid];

      #if DEBUG_TRACES
      trace("spawn " + pidString(p, lpid), LOG_SCHED);
      #end

      return fullPid(p.hpid, lpid);
   }

   inline function run_current() {
      p_did_yield = false;
      Reflect.callMethod(act_p.cobj, act_p.cont, act_p.cargs);
      
      if (!p_did_yield) {
         terminate_current();
      }
   }

   function terminate_current() {
      #if DEBUG_TRACES
      trace("terminating", LOG_SCHED);
      #end

      act_p.cobj = null;
      act_p.cont = null;
      act_p.cargs = null;
      act_p = null;
      active_lpids.mark_unlink();
      free_lpids.add(cur_lpid);
      proc_num--;
   }

   function pidString(?p: ProcEntry, ?lpid: Int, with_name = true) {
      if (p == null) {
         p = act_p;
         lpid = cur_lpid;
      }

      return "<" + (if (p != null) {
         var s = StringTools.hex(lpid) + "." + StringTools.hex(p.hpid);
         if (with_name && p.name != null) 
            s + " " + p.name
         else
            s;
      }
      else {
         "sched";
      }) + ">";
   }

   public function start() {
      Lib.current.addEventListener(Event.ENTER_FRAME, onEnterFrame);
   }

   inline function getT() {
      return Lib.getTimer();
   }

   inline public function getDelta() {
      return f_delta;
   }

   inline public function getFrameT() {
      return act_f_start;
   }

   function onEnterFrame(e) {
      last_f_start = act_f_start;
      act_f_start = getT();

      f_delta = act_f_start - last_f_start;
      var cur_overhead = f_delta - ideal_frame_delta;
      
      // adjust expected overhead
      render_overhead = Std.int(0.9 * render_overhead + 0.1 * cur_overhead);
      
      updateTargetDelta();

      // set the end of calculations this frame
      f_shed_end = act_f_start + target_frame_delta;

      run();
      #if ISTAT 
      trace("frame stat:"
            + " f_start=" + act_f_start
            + " now=" + getT() 
            + " f_shed_end=" + f_shed_end 
            + " cycles=" + run_cycles
      );
      #end
   }

   function run() {

      #if ISTAT run_cycles = 0; #end

      var c = 0;
      var c_val = 20;
      var check: Int = c_val;

      while 
         //(run_cycles < 10) { 
         (check != 0 || (getT() < f_shed_end)) { 
 
         if (--check == -1) {
            check = c_val;
         }

         active_lpids.advance();
         cur_lpid = active_lpids.next();

         if (cur_lpid == -1) {
            #if ISTAT run_cycles++; #end
            continue;
         }

         c++;
         
         act_p = pool[cur_lpid];

         switch (act_p.state) {
            case PNew:
               // will run in next cycle
               act_p.state = PRun;
      
               #if DEBUG_TRACES
               trace("ready", LOG_SCHED);
               #end

            case PRun:
               run_current();

            case PSleep:
               if (act_f_start > act_p.timer) {
                  act_p.state = PRun;

                  run_current();
               }

            
         }
         
         act_p = null;

      }

      if (proc_num == 0) {
         trace("no more processes to run", LOG_SCHED);
         Lib.current.removeEventListener(Event.ENTER_FRAME, onEnterFrame);
      }

   }

   // Quite inaccurate timer, for frame-skip purposes.
   //
   // msec is offset not from the current time, but from the start of
   // this frame. The process is woken in the frame whose start is 
   // after the resulting time.
   //
   // Call with msec=0 for sleeping until next frame
   public function sleep(msec: Int, cont: ContT, ?cargs: Array<Dynamic>) {
      act_p.state = PSleep;
      act_p.timer = act_f_start + msec;

      yield(cont, cargs);
   }

   public function yield(cont: ContT, ?cargs: Array<Dynamic>) {
      if (cont == null) {
         /// ??? is this required
         cont = act_p.cont;
      }

      if (cargs == null) {
         cargs = [];
      }

      act_p.cont = cont;
      act_p.cargs = cargs;
      p_did_yield = true;
   }

   public function getProcCount() {
      return proc_num;
   }

   public function setTrace() {
      var old_trace = haxe.Log.trace;
      
      var me = this;
      haxe.Log.trace = function(v: Dynamic, ?pos: haxe.PosInfos) {
         var from_sched = (pos.customParams != null) && (pos.customParams.length > 0) 
               && pos.customParams[0] == LOG_SCHED;

         var s = 
               (if (from_sched) 
                  "<sched>" +
                  (if (me.act_p != null) me.pidString() else "") 
               else 
                  me.pidString()) + " " + v;
         old_trace(s, {className: "", methodName: "", fileName: "", lineNumber: 0, customParams: null});

      };
   }

   // ----- general state -----

   // the process pool
   var pool: Array<ProcEntry>;

   // count of running processes
   var proc_num: Int;

   // currently running lpids;
   var active_lpids: CGList<Int>;

   // currently free lpids, which were used
   // sometime in the past
   var free_lpids: List<Int>;

   // ----- timing state -----

   // all time values are in milliseconds

   // duration a frame should take, based on FPS (1000 / FPS)
   var ideal_frame_delta: Int;

   // duration our calculations should last, taking into account
   // rendering duration
   var target_frame_delta: Int;

   // duration of the rendering (averaged)
   var render_overhead: Int;

   // time of start of last and actual frame
   var last_f_start: Int;
   var act_f_start: Int;

   // time between start if last and act frame (??? redundancy)
   var f_delta: Int; 

   // time until calculations for the frame should end
   var f_shed_end: Int;

   // ----- process state ----- 
 
   // index of the current process
   var cur_lpid: Int;

   // ProcEntry of actual process
   var act_p: ProcEntry;

   // did the actual process return control gracefully?
   var p_did_yield: Bool;

   #if ISTAT
   // ----- internal statistics -----

   var run_cycles: Int;
   #end

   // ----- constants -----

   // log is traced by scheduler
   inline static var LOG_SCHED = 0;
   
   // number of maximum concurrent processes
   inline static var MAX_PROC = 100000;

}


