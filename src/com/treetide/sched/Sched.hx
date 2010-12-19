/*
   Copyright (c) 2010, the haXe Project Contributors
   All rights reserved.

   Redistribution and use in source and binary forms, with or without
   modification, are permitted provided that the following conditions are met:

      * Redistributions of source code must retain the above copyright
        notice, this list of conditions and the following disclaimer.

      * Redistributions in binary form must reproduce the above copyright
        notice, this list of conditions and the following disclaimer in the
        documentation and/or other materials provided with the distribution.

   THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
   ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
   WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
   DISCLAIMED. IN NO EVENT SHALL THE HAXE PROJECT CONTRIBUTORS BE LIABLE FOR ANY
   DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
   (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
   LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
   ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
   (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
   SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

package com.treetide.sched;

// Accepted compile-time defines
//
// NDEBUG - turn off assertions
// TTS_ISTAT - turn on internal statistics collection
// TTS_DEBUG_TRACES - turn on debug traces

#if flash
import flash.Lib;
import flash.events.Event;
#end

enum ExitStatus {
   ESNormal;
   ESUnexpectMsg;
   ESAbnormal(reason: Dynamic);
   ESKilled;
}

// Process state
//
enum PState {
   PNew;
   PRun;
   PSleep;
   PMWait;
   PTerm;
}

// The continuation type, a function taking
// any number of arguments and returning Void
//
// Note: not really a true continuation
//
typedef ContT = Dynamic;

// The PID type of processes as visible to the user
//
// Currently it is built as (hpid << 16) | (lpid),
// where both hpid and lpid are 16bits long.
//
// - lpid is the process index in the process pool array
//
// - hpid is the reuse counter of that pool slot, so
//   a message won't be delivered to an unintended
//   process occupying the same slot
//
// The internals may change in the future
//
typedef PidT = Int;

// Process entry
//
typedef ProcEntry = {
   var state: PState;
   
   // continuation function to call next
   // and its arguments
   // cobj is the call context for reflection
   //
   var cobj: Dynamic;
   var cont: ContT;
   var cargs: Array<Dynamic>;

   // continuation on special timeout (from PMWait)
   // it is called with the same arguments as the default continuation
   //
   var timeout_cont: ContT;

   // optional name of the process
   //
   var name: String;

   // high 16 bit of pid (index-reuse counter)
   //
   var hpid: Int;

   // timer variable, used depending on state
   //
   // PSleep: 
   //    The wake-up time. Will be woken if the 
   //    current frame_start >= timer.
   //
   // PMWait:
   //    Waits for suitable message to arrive. If not arrived when
   //    frame_start >= timer, the process continues with timeout_cont
   //    
   var timer: Int;

   // message queue
   //
   var mq: MList<Dynamic>;

   // TODO:
   // waiting for pids, etc
}

// The scheduler manager
//
// M, because it it short (will write this a couple of times)
// and not S, because M is aesthetically more pleasing ;)
//
class M {

   // Singleton accessor
   //
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
 
      #if TTS_ISTAT
      frame_count = 0;
      #end

      proc_num = 0;
      run_proc_num = 0;

      daemons = new IntHash();
   }

   // Calculate how long should our calculations take 
   // from the total ideal frame time
   //
   inline function updateTargetDelta() {
      target_frame_delta = ideal_frame_delta - render_overhead;
   }

   // Sets the targeted frame rate of the software
   //
   public function setFps(fps: Int) {
      ideal_frame_delta = Std.int(1000 / fps);

      // initial guess
      render_overhead = 5;

      updateTargetDelta();
   }

   // Starts the scheduler
   //
   public function start() {
      Lib.current.addEventListener(Event.ENTER_FRAME, onEnterFrame);
   }

   // Creates an new process entry
   //
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

   // Reinitialized a process entry
   //
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

   // Retrieves a pool slot for the new process
   //
   function newLPid(cobj: Dynamic, f: ContT, args: Array<Dynamic>, name: String): Int {
      var new_lpid = if (free_lpids.isEmpty()) {
         // we have to extend the pool
         #if !NDEBUG
         if (pool.length == MAX_PROC) {
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

      // insert into the active list
      //
      // this process will practically execute only on the next cycle,
      // to avoid starving other processes by a recursive spawn chain
      //
      // however there is NO GUARANTEE about execution ordering,
      // so a user must not count on this
      active_lpids.spawn(new_lpid); 

      return new_lpid;
   }

   // assemble the pid from the parts
   //
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

   // transit process state
   //
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
               throw "! ~PRun (now " + p.state + ") -> PSleep/PMWait" + getStacks();
            }
            #end
            run_proc_num--;

         case PTerm:
            #if !NDEBUG
            if (!Type.enumEq(p.state, PRun)) {
               throw "! ~PRun -> PTerm" + getStacks();
            }
            #end
            proc_num--;
            run_proc_num--;
      } 
      p.state = new_state;
   }

   // continues the current process
   //
   inline function run_current() {
      p_did_yield = false;
      was_running++;

      try {
         Reflect.callMethod(act_p.cobj, act_p.cont, act_p.cargs);
      }
      catch (e: Dynamic) {
         trace("! process death, reason: " + Std.string(e) 
               + getStacks() );

         // TODO more sophisticated handling
         p_did_yield = false;
         throw e;
      }
      
      if (!p_did_yield) {
         // not yielding/sleeping/etc is an implicit termination
         terminate_current();
      }
   }

   // stack trace helper
   //
   function getStacks() {
      return 
            "\nName: " + (act_p == null ? "<null-proc>" : act_p.name)
            + "\nException stack:\n" 
            + haxe.Stack.toString(haxe.Stack.exceptionStack()) 
            + "\nCall stack:\n" 
            + haxe.Stack.toString(haxe.Stack.callStack());
   }

   // terminates and clears the current process
   //
   function terminate_current() {
      #if TTS_DEBUG_TRACES
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

      // don't null the pool slot, since
      // the process entry will be reused
   }

   // string representation of the pid, without process name,
   // only for tracing purposes (may change)
   //
   function pidStringRaw(pid: PidT) {
      return "<"  
         + StringTools.hex(lPid(pid)) 
         + "." 
         + StringTools.hex(hPid(pid))
         + ">";
   }

   // string representation of the pid of the current process
   // (or the process identified by the params)
   //
   // may change
   //
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

   // Returns the current timestamp as seconds
   //
   inline function getT() {
      #if flash
      return Lib.getTimer();
      #end
   }

   // Returns the time passed between start of the
   // last and act frame.
   //
   // Users are encouraged to use this method.
   //
   inline public function getDelta() {
      return f_delta;
   }

   // Return the time as visible to the user. 
   //
   // Users are encouraged to use this method
   // instead of directly calling the platforms timestamp
   // method, since the Scheduler may be able to freeze
   // time then for debugging, etc.
   //
   inline public function getUserT() {
      return act_f_start;
   }

   // Returns the start of the act frame
   //
   inline function getFrameT() {
      return act_f_start;
   }

   // Main loop function
   //
   function onEnterFrame(e) {
      last_f_start = act_f_start;
      act_f_start = getT();

      f_delta = act_f_start - last_f_start;
      var cur_overhead = f_delta - ideal_frame_delta;

      // adjust expected rendering overhead by simple running averaging
      render_overhead = Std.int(0.9 * render_overhead + 0.1 * cur_overhead);
      
      // recalculate the time allocated to this calculation batch
      updateTargetDelta();

      // set the end of calculations this frame
      f_shed_end = act_f_start + target_frame_delta;

      // run calculation batch
      run();

      #if TTS_ISTAT 
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

   // Iterates over processes and runs them until the allocated time
   // is up.
   //
   // Only checks time after running a couple of processes, because the
   // getTimer call is quite costy.
   //
   // TODO:
   //    - improve time checking strategy
   //    - or enable manual intervention/tuning using api
   //
   function run() {

      #if TTS_ISTAT 
      proc_spawned = 0;
      #end

      // number of cycles completed in this run
      run_cycles = 0; 

      // check cycle length
      var c_val = 20;

      // remaining time check is performed when check == 0
      var check: Int = c_val;

      // run at least one cycle (if there is time)
      was_running = 1; 
      var go = true;

      while (
         go && (check != 0 || getT() < f_shed_end) ) { 

         if (--check == -1) {
            // schedule next check
            check = c_val;
         }

         active_lpids.advance();
         cur_lpid = active_lpids.next();

         if (cur_lpid == -1) {
            // guard element reached, next cycle begins
            run_cycles++;
            
            // go only if not all processes were sleeping/waiting
            // during the last cycle
            go = was_running > 0;

            // reset active process count for the next cycle
            was_running = 0;

            continue;
         }

         // handle process entry
         act_p = pool[cur_lpid];

         switch (act_p.state) {
            case PNew:
               // will run in next cycle
               pState(act_p, PRun);
      
               #if TTS_DEBUG_TRACES
               trace("ready", LOG_SCHED);
               #end

            case PRun:
               // running
               run_current();

            case PSleep:
               // sleeping
               if (getUserT() > act_p.timer) {
                  pState(act_p, PRun);

                  run_current();
               }

            case PMWait:
               // waiting for message

               p_did_refuse = false;
               var has_new_msg = act_p.mq.peek_next() != null;

               if (has_new_msg) {
                  // make the process check if the
                  // message is acceptable for it
                  pState(act_p, PRun);
                  run_current();

                  if (p_did_yield) {
                     if (p_did_refuse) {
                        // not acceptable, keep waiting
                        act_p.mq.advance();
                        pState(act_p, PMWait);
                     }
                     else {
                        // message accepted, sink it
                        act_p.mq.consume();
                     }
                  }
                  // else was terminated
               }
               
               // if no acceptable message is received after the
               // timeout (if set), then wake process
               if ( (!has_new_msg || p_did_yield && p_did_refuse) 
                     && act_p.timer != NO_TIMER 
                     && getUserT() > act_p.timer) {
                  
                  // if set, wake the process with the timeout_cont
                  if (act_p.timeout_cont != null) {
                     act_p.cont = act_p.timeout_cont;
                     act_p.timeout_cont = null;
                  }

                  // rewind the message queue to the head
                  act_p.mq.rewind();
                  
                  // let it go
                  pState(act_p, PRun);
                  run_current();
               }

            case PTerm:
               throw "! PTerm scheduled for running";
            
         }
         
         act_p = null;

      }
      
      // If no more processes are to be run, scheduling is over.
      // Generally this should not happen.
      if (proc_num == 0) {
         trace("no more processes to run", LOG_SCHED);
         Lib.current.removeEventListener(Event.ENTER_FRAME, onEnterFrame);
      }
   }

   //
   // ---------- USER PROCESS API -----------
   //

   // Spawn a new process
   //
   public function spawn(cobj: Dynamic, cont: ContT, ?args: Array<Dynamic>, ?name: String): PidT {
      if (args == null) {
         args = [];
      }

      var lpid = newLPid(cobj, cont, args, name);
      var p = pool[lpid];

      pState(p, PNew);

      #if TTS_DEBUG_TRACES
      trace("spawn " + pidString(p, lpid), LOG_SCHED);
      #end

      #if TTS_ISTAT
      proc_spawned++;
      #end

      return fullPid(p.hpid, lpid);
   }

   // Register a daemon
   //
   public function registerD(reference: Int, pid: PidT) {
      daemons.set(reference, pid);
   }

   // Fetch a daemon
   //
   public function getD(reference: Int): PidT {
      return daemons.get(reference);
   }

   // Make the process sleep.
   //
   // Quite inaccurate timer, for frame-skip purposes.
   //
   // msec is offset not from the current time, but from the start of
   // this frame. The process is woken in the frame whose start is 
   // after the resulting time.
   //
   // Call with msec=0 for sleeping until next frame
   //
   public function sleep(msec: Int, ?cont: ContT, ?cargs: Array<Dynamic>) {
      pState(act_p, PSleep);
      act_p.timer = getUserT() + msec;

      yield(cont, cargs);
   }

   // Return with yield() to give up control and continue with the
   // current method (and arguments) next time.
   //
   // Can also set a new continuation using the parameters. If
   // a new continuation is set but parameters are not, then
   // the new continuation is called without parameters.
   //
   public function yield(?cont: ContT, ?cargs: Array<Dynamic>) {
      // cont, cargs -> update both
      // cont -> update cont, cargs = []
      // null, cargs -> update cargs, keep cont
      // (nothing) -> keep everything as-is

      if (cont != null) {
         act_p.cont = cont;
      
         if (cargs == null) {
            cargs = [];
         }
      }
      
      if (cargs != null) {
         act_p.cargs = cargs;
      }

      p_did_yield = true;
   }

   // Convenience return function for explicit termination
   //
   public function terminate(?exit_status: ExitStatus): Void {
      if (exit_status != null) {
         switch (exit_status) {
            case ESUnexpectMsg: throw "XXX msg";
            case ESAbnormal(m): throw "XXX";
            default: // TODO
         }
      }
   }

   // Return with recv() to enter message waiting state
   //
   // "timeout" is in msec, if no acceptable message is received after
   // the specified timeout (that is, no new message, or all new messages
   // were refused), then the process state is set to PRun and the
   // continuation "to_cont" is called with "cargs", if "to_cont" is
   // supplied, else "cont" is called
   //
   // "timeout" semantics is the same as "msec" of "sleep()"
   //
   // On a reception of a new message, "cont" is called with "cargs"
   //
   // cargs semantics is the same as that of yield()
   //
   public function recv(
         ?timeout: Int, 
         ?cont: ContT, ?cargs: Array<Dynamic>, 
         ?to_cont: ContT): Void {

      pState(act_p, PMWait);

      if (timeout == null) {
         act_p.timer = NO_TIMER;
      }
      else {
         act_p.timer = getUserT() + timeout;
         act_p.timeout_cont = to_cont;
      }

      yield(cont, cargs);
   }

   // Peeks at the current message of the inbox, but
   // does not remove it.
   //
   // Returns null if no message.
   //
   public function peek() {
      return act_p.mq.peek_next();
   }

   // Consumes and returns the current message, and rewinds
   // the inbox. If no message is available, returns null
   // and does not rewind.
   //
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
   //
   // Use it with care.
   //
   public function flush() {
      act_p.mq.flush();
   }

   // Return from a message handler continuation with refuse() if
   // the received message is not the expected. Advances the inbox.
   //
   public function refuse(): Void {
      p_did_refuse = true;

      yield(act_p.cont, act_p.cargs);
   }

   // Send a message "m" to "pid"
   //
   public function msg(pid: PidT, m: Dynamic): Void {
      var lpid = lPid(pid);
      var target = pool[lpid];

      if (target == null || target.cont == null || target.hpid != hPid(pid)) {
         #if TTS_DEBUG_TRACES
         trace("target " + pidStringRaw(pid) + " not exists", LOG_SCHED);
         #end
         return;
      }

      target.mq.add(m);
   }

   // Returns the pid of the current process
   //
   public function pid(): PidT {
      return fullPid(act_p.hpid, cur_lpid);
   }

   // Returns the number of processes
   //
   public function getProcCount(): Int {
      return proc_num;
   }

   // Replaces the default trace function with one
   // prepending the current process information
   //
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
                  me.pidString()) + " " + v; // + " @" + me.getUserT();
         old_trace(s, {className: "", methodName: "", fileName: "", lineNumber: 0, customParams: null});

      };
   }

   // ----- general state -----

   // the process pool
   var pool: Array<ProcEntry>;

   // count of active processes
   var proc_num: Int;

   // count of processes in PNew or PRun
   // (TODO: separate CGLists for sleeping/mwaiting processes, if it is worth it)
   var run_proc_num: Int;

   // currently running lpids;
   var active_lpids: CGList<Int>;

   // currently free lpids, which were used
   // sometime in the past
   var free_lpids: List<Int>;

   // cycles made in the scheduler loop in the current frame
   var run_cycles: Int;

   // number of processes actually entering run state under the last
   // cycle of the actual loop
   var was_running: Int;

   // daemon registry
   var daemons: IntHash<PidT>;

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

   // time between start of last and act frame (??? redundancy)
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

   #if TTS_ISTAT
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
