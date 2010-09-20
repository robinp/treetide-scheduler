package com.treetide.sched;

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
   PMWait;
   PTerm;
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

   // continuation on special timeout (from PMWait)
   // it is called with the same arguments as the default continuation
   var timeout_cont: ContT;

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

   // message queue
   var mq: MList<Dynamic>;

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
 
      #if ISTAT
      frame_count = 0;
      #end

      proc_num = 0;
      run_proc_num = 0;
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
      return {
         state: PNew, 
         cobj: cobj, 
         cont: f,
         timeout_cont: null,
         cargs: args, 
         name: name, 
         hpid: 0, 
         timer: 0,
         mq: new MList<Dynamic>()
      };
   }

   inline function resetEntry(e: ProcEntry, cobj: Dynamic, f: ContT, args: Array<Dynamic>, name: String) {
      e.state = PNew;
      e.cobj = cobj;
      e.cont = f;
      e.timeout_cont = null;
      e.cargs = args;
      e.name = name;
      // e.timer is not valid in PNew so not reset
      // e.mq.reinit() is already done at terminate

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

      return new_lpid;
   }

   inline function fullPid(hpid: Int, lpid: Int) {
      #if !NDEBUG
      if ((lpid & 0xFFFF) != lpid) 
         throw "! LPID must be <= 0xFFFF";
      #end
      return (hpid << 16) | lpid;
   }

   inline function lPid(pid: PidT): Int {
      return pid & 0xFFFF;
   }
   
   inline function hPid(pid: PidT): Int {
      return pid >>> 16;
   }

   function pState(p: ProcEntry, new_state: PState) {
      //trace("from " + p.state + " to " + new_state);
      switch (new_state) {
         case PNew:
            proc_num++;
            run_proc_num++;

         case PRun:
            switch (p.state) {
               case PNew:
                  // pass
               default:
                  run_proc_num++;
            }

         case PSleep, PMWait:
            #if !NDEBUG
            if (!Type.enumEq(p.state, PRun)) {
               throw "! ~PRun -> PSleep/PMWait";
            }
            #end
            run_proc_num--;

         case PTerm:
            #if !NDEBUG
            if (!Type.enumEq(p.state, PRun)) {
               throw "! ~PRun -> PTerm";
            }
            #end
            proc_num--;
            run_proc_num--;
      } 
      p.state = new_state;
   }

   public function spawn(cobj: Dynamic, cont: ContT, ?args: Array<Dynamic>, ?name: String): PidT {
      if (args == null) {
         args = [];
      }

      var lpid = newLPid(cobj, cont, args, name);
      var p = pool[lpid];

      pState(p, PNew);

      #if DEBUG_TRACES
      trace("spawn " + pidString(p, lpid), LOG_SCHED);
      #end

      #if ISTAT
      proc_spawned++;
      #end

      return fullPid(p.hpid, lpid);
   }

   inline function run_current() {
      p_did_yield = false;

      try {
         Reflect.callMethod(act_p.cobj, act_p.cont, act_p.cargs);
      }
      catch (e: Dynamic) {
         trace("! process death, reason: " + Std.string(e) 
               + "\nException stack:\n" + haxe.Stack.toString(haxe.Stack.exceptionStack()) 
               + "\nCall stack:\n" + haxe.Stack.toString(haxe.Stack.callStack()) );

         // TODO more sophisticated handling
         p_did_yield = false;
      }
      
      if (!p_did_yield) {
         terminate_current();
      }
   }

   function terminate_current() {
      #if DEBUG_TRACES
      trace("terminating", LOG_SCHED);
      #end

      pState(act_p, PTerm);
      act_p.cobj = null;
      act_p.cont = null;
      act_p.timeout_cont = null;
      act_p.cargs = null;
      act_p.name = null;
      act_p.mq.reinit();
      act_p = null;
      active_lpids.mark_unlink();
      free_lpids.add(cur_lpid);
      // don't null the pool, since it will be reused
   }

   function pidStringRaw(pid: PidT) {
      return "<"  
         + StringTools.hex(lPid(pid)) 
         + "." 
         + StringTools.hex(hPid(pid))
         + ">";
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

   inline function getFrameT() {
      return act_f_start;
   }

   // return the time as visible to the user
   inline public function getUserT() {
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
      var now = getT();
      if (frame_count++ % 300 == 0)
         trace("frame stat:"
               + " f_start=" + act_f_start
               + " end_acc=" + (now - f_shed_end)
               + " cycles=" + run_cycles
               + " proc=" + proc_num
               + " run_proc=" + run_proc_num
         );
      #end
   }

   function run() {

      #if ISTAT 
      proc_spawned = 0;
      #end

      run_cycles = 0; 
      var c = 0;
      var c_val = 20;
      var check: Int = c_val;

      while (
          (run_cycles < 2 || run_proc_num > 0) && 
          (check != 0 || getT() < f_shed_end) ) { 
 
         if (--check == -1) {
            check = c_val;
         }

         active_lpids.advance();
         cur_lpid = active_lpids.next();

         if (cur_lpid == -1) {
            run_cycles++;
            continue;
         }

         c++;
         
         act_p = pool[cur_lpid];

         switch (act_p.state) {
            case PNew:
               // will run in next cycle
               pState(act_p, PRun);
      
               #if DEBUG_TRACES
               trace("ready", LOG_SCHED);
               #end

            case PRun:
               run_current();

            case PSleep:
               if (act_f_start > act_p.timer) {
                  pState(act_p, PRun);

                  run_current();
               }

            case PMWait:
               if (act_p.mq.peek_next() != null) {
                  p_did_refuse = false;
                  pState(act_p, PRun);
                  run_current();

                  if (p_did_yield) {
                     if (p_did_refuse) {
                        act_p.mq.advance();
                        pState(act_p, PMWait);
                     }
                     else {
                        act_p.mq.consume();
                     }
                  }
                  // else was terminated
               }

            case PTerm:
               throw "! PTerm scheduled for running";
            
         }
         
         act_p = null;

      }

      if (proc_num == 0) {
         trace("no more processes to run", LOG_SCHED);
         Lib.current.removeEventListener(Event.ENTER_FRAME, onEnterFrame);
      }
   }

   //
   // ---------- USER PROCESS API -----------
   //

   // Quite inaccurate timer, for frame-skip purposes.
   //
   // msec is offset not from the current time, but from the start of
   // this frame. The process is woken in the frame whose start is 
   // after the resulting time.
   //
   // Call with msec=0 for sleeping until next frame
   public function sleep(msec: Int, cont: ContT, ?cargs: Array<Dynamic>) {
      pState(act_p, PSleep);
      act_p.timer = act_f_start + msec;

      yield(cont, cargs);
   }

   // Return with yield() to give up control
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

   // Convenience return function for explicit termination
   public function terminate(): Void {
   }

   // Return with recv() to enter message waiting state
   public function recv(cont: ContT, ?cargs: Array<Dynamic>, 
         ?timeout: Int, ?to_cont: ContT): Void {
      pState(act_p, PMWait);

      if (timeout == null) {
         act_p.timer = NO_TIMER;
      }
      else {
         act_p.timer = timeout;
         act_p.timeout_cont = to_cont;
      }

      yield(cont, cargs);
   }

   // Peeks at the current message of the inbox, but
   // does not remove it. Returns null if no message.
   public function peek() {
      return act_p.mq.peek_next();
   }

   // Consumes and returns the current message, and rewinds
   // the inbox. If no message is available, returns null
   // and does not rewind.
   public function consume() {
      var m = act_p.mq.peek_next();
      return if (m == null) {
         null;
      } 
      else {
         act_p.mq.consume();
         m;
      }
   }

   // Clears the inbox
   public function flush() {
      act_p.mq.flush();
   }

   // Return from a message handler continuation with refuse() if
   // the received message is not the expected. Advances the inbox.
   public function refuse(): Void {
      p_did_refuse = true;

      yield(act_p.cont, act_p.cargs);
   }

   // Send a message "m" to "pid"
   // If type(pid)=PidT: never fails
   // If type(pid)=NameT: fails if non-existent name

   public function msg(pid: PidT, m: Dynamic): Void {
      var lpid = lPid(pid);
      var target = pool[lpid];

      if (target == null || target.cont == null || target.hpid != hPid(pid)) {
         #if DEBUG_TRACES
         trace("target " + pidStringRaw(pid) + " not exists", LOG_SCHED);
         #end
         return;
      }

      target.mq.add(m);
   }

   public function getMyPid() {
      return fullPid(act_p.hpid, cur_lpid);
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

   // count of active processes
   var proc_num: Int;

   // count of processes in PNew or PRun
   // (TODO: separate CGLists for sleeping/mwaiting processes)
   var run_proc_num: Int;

   // currently running lpids;
   var active_lpids: CGList<Int>;

   // currently free lpids, which were used
   // sometime in the past
   var free_lpids: List<Int>;

   // cycles made in the scheduler loop in the current frame
   var run_cycles: Int;

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

   // did the actual process refuse the message?
   var p_did_refuse: Bool;

   #if ISTAT
   // ----- internal statistics -----

   var frame_count: UInt;
   var proc_spawned: Int;
   #end

   // ----- constants -----

   // log is traced by scheduler
   inline static var LOG_SCHED = 0;
 
   // no timer set
   inline static var NO_TIMER = -1;

   // number of maximum concurrent processes
   inline static var MAX_PROC = 100000;

}


