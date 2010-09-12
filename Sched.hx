// Defines:
//
// NDEBUG - turn off assertions
// POOL_MAX - turn on maximum process number checking
// DEBUG_TRACES - turn on debug traces

enum PState {
   PNew;
   PRun;
   PSleep;
}

typedef ContT = Void -> Void;

typedef PidT = Int;

typedef ProcEntry = {
   // process state
   var state: PState;
   
   // continuation function to call next
   var cont: ContT;

   // optional name of the process (??? mapped opt)
   var name: String;

   // high 16 bit of pid (index-reuse counter)
   var hpid: Int;

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
      active_lpids = new CGList(-1);
      free_lpids = new List();
      
      proc_num = 0;
   }

   inline function emptyEntry(f: ContT, name: String) {
      return {state: PNew, cont: f, name: name, hpid: 0};
   }

   inline function resetEntry(e: ProcEntry, f: ContT, name: String) {
      e.state = PNew;
      e.cont = f;
      e.name = name;

      e.hpid++;
      if (e.hpid == 0x7FFF) {
         // turn it around
         e.hpid = 0;
      }
   }

   function newLPid(f: ContT, name: String): Int {
      var new_lpid = if (free_lpids.isEmpty()) {
         // we have to extend the pool
         #if POOL_MAX
         if (proc_pool.length == MAX_PROC) {
            throw "! Maximum number of processes reached (" + MAX_PROC + ")";
         }
         #end

         pool.push(emptyEntry(f, name));
         pool.length - 1;
      }
      else {
         var lpid = free_lpids.pop();
         resetEntry(pool[lpid], f, name);
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

   public function spawn(cont: ContT, ?name: String): PidT {
      var lpid = newLPid(cont, name);
      var p = pool[lpid];

      #if DEBUG_TRACES
      trace("spawn " + pidString(p, lpid), LOG_SCHED);
      #end

      return fullPid(p.hpid, lpid);
   }

   function terminate_current() {
      #if DEBUG_TRACES
      trace("terminating", LOG_SCHED);
      #end

      act_p.cont = null;
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

      while (proc_num > 0) {
         active_lpids.advance();
         cur_lpid = active_lpids.next();

         if (cur_lpid == -1)
            continue;

         act_p = pool[cur_lpid];

         switch (act_p.state) {
            case PNew:
               // will run in next cycle
               act_p.state = PRun;
      
               #if DEBUG_TRACES
               trace("ready", LOG_SCHED);
               #end

            case PRun:
               p_did_yield = false;
               act_p.cont();
               
               if (!p_did_yield) {
                  terminate_current();
               }

            case PSleep:
               throw "implement sleep";
         }
         
         act_p = null;

      }

      trace("no more processes to run", LOG_SCHED);

   }

   public function yield(cont: ContT) {
      act_p.cont = cont;
      p_did_yield = true;
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

   // the process pool
   var pool: Array<ProcEntry>;

   // count of running processes
   var proc_num: Int;

   // index of the current process
   var cur_lpid: Int;

   // currently running lpids;
   var active_lpids: CGList<Int>;

   // currently free lpids, which were used
   // sometime in the past
   var free_lpids: List<Int>;

   // -----
   var p_did_yield: Bool;
   var act_p: ProcEntry;

   // ----- constants -----

   // log is traced by scheduler
   inline static var LOG_SCHED = 0;
   
   // number of maximum concurrent processes
   inline static var MAX_PROC = 100000;

}


