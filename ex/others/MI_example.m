-- MI_example protocol
----------------------------------------------------------------------
-- Constants
----------------------------------------------------------------------
const
  L1CacheCount: 2;          -- number processors
  ValueCount: 2;       -- number of data values.
  VC0: 0;
  VC1: 1;
  VC2: 2;
  VC3: 3;
  VC4: 4;
  NumVCs: VC4 - VC0 + 1;
  NetMax: L1CacheCount + 10;
    
------------------------------------------------------------
-- Types
------------------------------------------------------------
type
  L1Cache: scalarset(L1CacheCount);
  Value: scalarset(ValueCount);
  Memory: enum { MemoryType };
  Directory: enum { DirectoryType };
  DMA: enum { DMAType };
  Node: union {Memory, L1Cache, Directory, DMA};

  VCType: VC0..NumVCs-1;
  CountType: 0..L1CacheCount;
  EventType: enum {
  L1Cache_Load,
  L1Cache_Ifetch,
  L1Cache_Store,
  L1Cache_Data,
  L1Cache_Fwd_GETX,
  L1Cache_Inv,
  L1Cache_Replacement,
  L1Cache_Writeback_Ack,
  L1Cache_Writeback_Nack,
  Directory_GETX,
  Directory_GETS,
  Directory_PUTX,
  Directory_PUTX_NotOwner,
  Directory_DMA_READ,
  Directory_DMA_WRITE,
  Directory_Memory_Data,
  Directory_Memory_Ack,
  DMA_ReadRequest,
  DMA_WriteRequest,
  DMA_Data,
  DMA_Ack,
  Memory_Read,
  Memory_WB,
  Memory_Data,
  Memory_Ack
              };
  MessageType: enum{
  CoherenceRequestType_GETS,
  CoherenceRequestType_GETX,
  CoherenceRequestType_INV,
  CoherenceRequestType_PUTX,
  CoherenceRequestType_WB_ACK,
  CoherenceRequestType_WB_NACK,
  CoherenceResponseType_DATA,
  DMARequestType_READ,
  DMARequestType_WRITE,
  DMAResponseType_ACK,
  DMAResponseType_DATA,
  MemoryRequestType_MEMORY_READ,
  MemoryRequestType_MEMORY_WB,
  RubyRequestType_IFETCH,
  RubyRequestType_LD,
  RubyRequestType_Replacement,
  RubyRequestType_ST,
  SequencerRequestType_LD,
  SequencerRequestType_ST
              };
Message:
  Record
    mtype:MessageType;
    dst:Node;
    src:Node;
    req:Node;
    vc:VCType;
    val:Value;
    cnt:CountType
  End;
  
L1CacheEntry:
  Record
    state: enum {L1Cache_I, L1Cache_II, L1Cache_M, L1Cache_MI, L1Cache_MII, L1Cache_IS, L1Cache_IM};
    val: Value;
    cnt: CountType;
    totalacks: CountType;
End;
DirectoryEntry:
  Record
    state: enum {Directory_I, Directory_M, Directory_M_DRD, Directory_M_DWR, Directory_M_DWRI, Directory_M_DRDI, Directory_IM, Directory_MI, Directory_ID, Directory_ID_W};
    owner: Node;
    sharers: multiset [L1CacheCount] of Node;
    val: Value;
End;
DMAEntry:
  Record
    state: enum {DMA_READY, DMA_BUSY_RD, DMA_BUSY_WR};
    val: Value;
End;
MemoryEntry:
  Record
    val: Value;
End;
    
L1CacheTBE:
  Record
    val: Value;
End;
DirectoryTBE:
  Record
    val: Value;
    DmaRequestor: Node;
End;
DMATBE:
  Record
    val: Value;
End;
------------------------------------------------------------------------
-- Variables
------------------------------------------------------------------------
var
  DirectoryNode: DirectoryEntry;
  DMANode: DMAEntry;
  DirectoryTBENode: DirectoryTBE;
  DMATBENode: DMATBE;
  MemoryNode: MemoryEntry;
  L1Caches: array[L1Cache] of L1CacheEntry;
  L1CacheTBEs: array[L1Cache] of L1CacheTBE;
  Net: array [Node] of multiset[NetMax] of Message;
  InBox: array [Node] of array [VCType] of Message;
  msg_processed: boolean;
  msg_recycled: boolean;
  LastWrite: Value;
    
----------------------------------------------------------------------------
-- Procedures
----------------------------------------------------------------------------
Procedure ErrorUnhandledMsg(msg: Message);
Begin
  put "\n" ;
  put "Unhandled message!\n" ;
  put "message source: " ;
  put msg.src;
  put "\n" ;
  put "message type: " ;
  put msg.mtype;
  put "\n" ;
  put "message destination: " ;
  put msg.dst;
  put "\n" ;
  put "message original requestor: " ;
  put msg.req;
  put "\n" ;
  put "message virtual channel: " ;
  put msg.vc;
  put "\n" ;
  put "message value: " ;
  put msg.val;
  put "\n" ;
  put "message count: " ;
  put msg.cnt;
  put "\n" ;
  put DirectoryNode.state;
  put DirectoryNode.owner;
  put "\n\n" ;
  error "Unhandled message type!"; 
End;

Procedure ErrorUnhandledState();
Begin
  error "Unhandled state!";
End;

Procedure ResetL1CacheEntry(c:L1Cache);
  undefine L1Caches[c].state;
  undefine L1Caches[c].val;
  undefine L1Caches[c].cnt;
  undefine L1Caches[c].totalacks;
End;
Procedure ResetL1CacheTBEEntry(c:L1Cache);
  undefine L1Caches[c].val;
End;

Procedure ResetDirectoryEntry();
  undefine DirectoryNode.state;
  undefine DirectoryNode.owner;
  undefine DirectoryNode.sharers;
  undefine DirectoryNode.val;
End;
Procedure ResetDirectoryTBEEntry();
  undefine DirectoryTBENode.val;
  undefine DirectoryTBENode.DmaRequestor;
End;

Procedure ResetDMAEntry();
  undefine DMANode.state;
  undefine DMANode.val;
End;
Procedure ResetDMATBEEntry();
  undefine DMATBENode.val;
End;

Procedure AddToDirectoryNodesharersList(n:Node);
Begin
  if MultiSetCount(i:DirectoryNode.sharers, DirectoryNode.sharers[i] = n) = 0
  then
    MultiSetAdd(n, DirectoryNode.sharers);
  endif;
End;

Procedure ClearDirectoryNodesharersList();
Begin
    for n:Node do
    if (IsMember(n, L1Cache) &
        MultiSetCount(i:DirectoryNode.sharers, DirectoryNode.sharers[i] = n) != 0)
      then
        MultiSetRemovePred(i:DirectoryNode.sharers, DirectoryNode.sharers[i] = n);
    endif;
  endfor;
End;

Function IsDirectoryNodesharers(n:Node) : Boolean;
Begin
  return MultiSetCount (i:DirectoryNode.sharers, DirectoryNode.sharers[i] = n) > 0
End;

Procedure RemoveFromDirectoryNodesharers(n:Node);
Begin
  MultiSetRemovePred(i:DirectoryNode.sharers, DirectoryNode.sharers[i] = n);
End;

---------------------------------------------------------------------------
-- Peek L1Cache's Message Buffer and Trigger an Event
--------------------------------------------------------------------------

Function L1CachePeek(msg : Message): EventType;
Begin
	switch msg.mtype
    case CoherenceRequestType_INV:
        return L1Cache_Inv;
    case CoherenceRequestType_WB_NACK:
        return L1Cache_Writeback_Nack;
    case CoherenceRequestType_WB_ACK:
        return L1Cache_Writeback_Ack;
    case CoherenceRequestType_GETX:
        return L1Cache_Fwd_GETX;
    case CoherenceResponseType_DATA:
        return L1Cache_Data;
    case RubyRequestType_LD:
        return L1Cache_Load;
    case RubyRequestType_IFETCH:
        return L1Cache_Ifetch;
    case RubyRequestType_ST:
        return L1Cache_Store;
    case RubyRequestType_Replacement:
        return L1Cache_Replacement;

	else
	    put "message type to L1Cache:";
	    put msg.mtype;
	    put "\n";
		error "Unhandled message type!";
	endswitch;
End;
---------------------------------------------------------------------------
-- Peek Directory's Message Buffer and Trigger an Event
--------------------------------------------------------------------------

Function DirectoryPeek(msg : Message): EventType;
Begin
	switch msg.mtype
    case DMARequestType_WRITE:
        return Directory_DMA_WRITE;
    case DMARequestType_READ:
        return Directory_DMA_READ;
    case CoherenceRequestType_GETX:
        return Directory_GETX;
    case CoherenceRequestType_GETS:
        return Directory_GETS;
    case MemoryRequestType_MEMORY_WB:
        return Directory_Memory_Ack;
    case MemoryRequestType_MEMORY_READ:
        return Directory_Memory_Data;
    case CoherenceRequestType_PUTX:
        if DirectoryNode.owner = msg.req
        then
          return Directory_PUTX;
        endif;
        return Directory_PUTX_NotOwner;

	else
	    put "message type to Directory:";
	    put msg.mtype;
	    put "\n";
		error "Unhandled message type!";
	endswitch;
End;
---------------------------------------------------------------------------
-- Peek DMA's Message Buffer and Trigger an Event
--------------------------------------------------------------------------

Function DMAPeek(msg : Message): EventType;
Begin
	switch msg.mtype
    case SequencerRequestType_ST:
        return DMA_WriteRequest;
    case SequencerRequestType_LD:
        return DMA_ReadRequest;
    case DMAResponseType_DATA:
        return DMA_Data;
    case DMAResponseType_ACK:
        return DMA_Ack;

	else
	    put "message type to DMA:";
	    put msg.mtype;
	    put "\n";
		error "Unhandled message type!";
	endswitch;
End;
Function MemoryPeek(msg : Message): EventType;
Begin
	switch msg.mtype
    case MemoryRequestType_MEMORY_READ:
        return Memory_Read;
    case MemoryRequestType_MEMORY_WB:
        return Memory_WB;
	else
	    put "unhandled message type to Memory:";
	    put msg.mtype;
	    put "\ndestination:";
	    put msg.dst;
	    put "\nsource:";
	    put msg.src;
	    put "\nrequestor:";
	    put msg.req;
	    put "\n";
		error "Unhandled message type!";
	endswitch;
End;
Procedure Send(mtype:MessageType;
		dst:Node;
		src:Node;
		req:Node;
		vc:VCType;
		val:Value;
		cnt:CountType
          );
var msg:Message;
Begin
  Assert (MultiSetCount(i:Net[dst], true) < NetMax) "Too many messages";

    msg.mtype := mtype;
	msg.dst := dst;
	msg.src := src;
	msg.req := req;
	msg.vc := vc;
	msg.val := val;
	msg.cnt := cnt;

  MultiSetAdd(msg, Net[dst]);
End;
---------------------------------------------------------------------------
-- Directory Communication
--------------------------------------------------------------------------

Procedure DirectoryReceive(msg: Message);
var cnt:0..L1CacheCount;   -- for counting sharers
var etype : EventType;   -- event type from peek
Begin
  cnt := MultiSetCount(i:DirectoryNode.sharers, true);
  alias tbe:DirectoryTBENode do
  alias DirectoryState:DirectoryNode.state do
  msg_processed :=  true;
  msg_recycled := false;
  etype := DirectoryPeek(msg);

  switch DirectoryState
  case Directory_M_DRD:
    switch etype
    case Directory_GETX:
      -- z_recycleRequestQueue
      msg_recycled := true;
      -- state_transition
      DirectoryState := Directory_M_DRD;
    case Directory_PUTX:
      -- drp_sendDMAData
      Send(DMAResponseType_DATA, tbe.DmaRequestor, UNDEFINED, UNDEFINED, 1, msg.val, UNDEFINED);
      -- c_clearOwner
      undefine DirectoryNode.owner;
      -- l_queueMemoryWBRequest
      Send(MemoryRequestType_MEMORY_WB, MemoryType, DirectoryType, msg.req, 0, msg.val, UNDEFINED);
      -- i_popIncomingRequestQueue
      -- state_transition
      DirectoryState := Directory_M_DRDI;
    case Directory_PUTX_NotOwner:
      -- b_sendWriteBackNack
      Send(CoherenceRequestType_WB_NACK, msg.req, DirectoryType, msg.req, 3, UNDEFINED, UNDEFINED);
      -- i_popIncomingRequestQueue
      -- state_transition
      DirectoryState := Directory_M_DRD;
    else
        ErrorUnhandledMsg(msg);
    endswitch;
                
  case Directory_M_DWR:
    switch etype
    case Directory_GETX:
      -- z_recycleRequestQueue
      msg_recycled := true;
      -- state_transition
      DirectoryState := Directory_M_DWR;
    case Directory_PUTX:
      -- qw_queueMemoryWBRequest_partialTBE
      Send(MemoryRequestType_MEMORY_WB, MemoryType, DirectoryType, msg.req, 0, tbe.val, UNDEFINED);
      -- c_clearOwner
      undefine DirectoryNode.owner;
      -- i_popIncomingRequestQueue
      -- state_transition
      DirectoryState := Directory_M_DWRI;
    case Directory_PUTX_NotOwner:
      -- b_sendWriteBackNack
      Send(CoherenceRequestType_WB_NACK, msg.req, DirectoryType, msg.req, 3, UNDEFINED, UNDEFINED);
      -- i_popIncomingRequestQueue
      -- state_transition
      DirectoryState := Directory_M_DWR;
    else
        ErrorUnhandledMsg(msg);
    endswitch;
                
  case Directory_M_DWRI:
    switch etype
    case Directory_GETX:
      -- z_recycleRequestQueue
      msg_recycled := true;
      -- state_transition
      DirectoryState := Directory_M_DWRI;
    case Directory_Memory_Ack:
      -- l_sendWriteBackAck
      Send(CoherenceRequestType_WB_ACK, msg.req, msg.req, msg.req, 3, UNDEFINED, UNDEFINED);
      -- da_sendDMAAck
      Send(DMAResponseType_ACK, tbe.DmaRequestor, UNDEFINED, UNDEFINED, 1, UNDEFINED, UNDEFINED);
      -- w_deallocateTBE
      ResetDirectoryTBEEntry();
      -- l_popMemQueue
      -- state_transition
      DirectoryState := Directory_I;
    case Directory_PUTX_NotOwner:
      -- b_sendWriteBackNack
      Send(CoherenceRequestType_WB_NACK, msg.req, DirectoryType, msg.req, 3, UNDEFINED, UNDEFINED);
      -- i_popIncomingRequestQueue
      -- state_transition
      DirectoryState := Directory_M_DWRI;
    else
        ErrorUnhandledMsg(msg);
    endswitch;
                
  case Directory_M_DRDI:
    switch etype
    case Directory_GETX:
      -- z_recycleRequestQueue
      msg_recycled := true;
      -- state_transition
      DirectoryState := Directory_M_DRDI;
    case Directory_DMA_WRITE:
      -- y_recycleDMARequestQueue
      msg_recycled := true;
      -- state_transition
      DirectoryState := Directory_M_DRDI;
    case Directory_DMA_READ:
      -- y_recycleDMARequestQueue
      msg_recycled := true;
      -- state_transition
      DirectoryState := Directory_M_DRDI;
    case Directory_Memory_Ack:
      -- l_sendWriteBackAck
      Send(CoherenceRequestType_WB_ACK, msg.req, msg.req, msg.req, 3, UNDEFINED, UNDEFINED);
      -- w_deallocateTBE
      ResetDirectoryTBEEntry();
      -- l_popMemQueue
      -- state_transition
      DirectoryState := Directory_I;
    case Directory_PUTX_NotOwner:
      -- b_sendWriteBackNack
      Send(CoherenceRequestType_WB_NACK, msg.req, DirectoryType, msg.req, 3, UNDEFINED, UNDEFINED);
      -- i_popIncomingRequestQueue
      -- state_transition
      DirectoryState := Directory_M_DRDI;
    else
        ErrorUnhandledMsg(msg);
    endswitch;
                
  case Directory_IM:
    switch etype
    case Directory_GETX:
      -- z_recycleRequestQueue
      msg_recycled := true;
      -- state_transition
      DirectoryState := Directory_IM;
    case Directory_GETS:
      -- z_recycleRequestQueue
      msg_recycled := true;
      -- state_transition
      DirectoryState := Directory_IM;
    case Directory_PUTX:
      -- z_recycleRequestQueue
      msg_recycled := true;
      -- state_transition
      DirectoryState := Directory_IM;
    case Directory_PUTX_NotOwner:
      -- z_recycleRequestQueue
      msg_recycled := true;
      -- state_transition
      DirectoryState := Directory_IM;
    case Directory_DMA_WRITE:
      -- y_recycleDMARequestQueue
      msg_recycled := true;
      -- state_transition
      DirectoryState := Directory_IM;
    case Directory_DMA_READ:
      -- y_recycleDMARequestQueue
      msg_recycled := true;
      -- state_transition
      DirectoryState := Directory_IM;
    case Directory_Memory_Data:
      -- d_sendData
      Send(CoherenceResponseType_DATA, msg.req, DirectoryType, msg.req, 4, msg.val, UNDEFINED);
      -- w_deallocateTBE
      ResetDirectoryTBEEntry();
      -- l_popMemQueue
      -- state_transition
      DirectoryState := Directory_M;
    else
        ErrorUnhandledMsg(msg);
    endswitch;
                
  case Directory_MI:
    switch etype
    case Directory_GETX:
      -- z_recycleRequestQueue
      msg_recycled := true;
      -- state_transition
      DirectoryState := Directory_MI;
    case Directory_GETS:
      -- z_recycleRequestQueue
      msg_recycled := true;
      -- state_transition
      DirectoryState := Directory_MI;
    case Directory_PUTX:
      -- z_recycleRequestQueue
      msg_recycled := true;
      -- state_transition
      DirectoryState := Directory_MI;
    case Directory_PUTX_NotOwner:
      -- z_recycleRequestQueue
      msg_recycled := true;
      -- state_transition
      DirectoryState := Directory_MI;
    case Directory_DMA_WRITE:
      -- y_recycleDMARequestQueue
      msg_recycled := true;
      -- state_transition
      DirectoryState := Directory_MI;
    case Directory_DMA_READ:
      -- y_recycleDMARequestQueue
      msg_recycled := true;
      -- state_transition
      DirectoryState := Directory_MI;
    case Directory_Memory_Ack:
      -- l_sendWriteBackAck
      Send(CoherenceRequestType_WB_ACK, msg.req, msg.req, msg.req, 3, UNDEFINED, UNDEFINED);
      -- w_deallocateTBE
      ResetDirectoryTBEEntry();
      -- l_popMemQueue
      -- state_transition
      DirectoryState := Directory_I;
    else
        ErrorUnhandledMsg(msg);
    endswitch;
                
  case Directory_ID:
    switch etype
    case Directory_GETX:
      -- z_recycleRequestQueue
      msg_recycled := true;
      -- state_transition
      DirectoryState := Directory_ID;
    case Directory_GETS:
      -- z_recycleRequestQueue
      msg_recycled := true;
      -- state_transition
      DirectoryState := Directory_ID;
    case Directory_PUTX:
      -- z_recycleRequestQueue
      msg_recycled := true;
      -- state_transition
      DirectoryState := Directory_ID;
    case Directory_PUTX_NotOwner:
      -- z_recycleRequestQueue
      msg_recycled := true;
      -- state_transition
      DirectoryState := Directory_ID;
    case Directory_DMA_WRITE:
      -- y_recycleDMARequestQueue
      msg_recycled := true;
      -- state_transition
      DirectoryState := Directory_ID;
    case Directory_DMA_READ:
      -- y_recycleDMARequestQueue
      msg_recycled := true;
      -- state_transition
      DirectoryState := Directory_ID;
    case Directory_Memory_Data:
      -- dr_sendDMAData
      Send(DMAResponseType_DATA, tbe.DmaRequestor, UNDEFINED, UNDEFINED, 1, msg.val, UNDEFINED);
      -- w_deallocateTBE
      ResetDirectoryTBEEntry();
      -- l_popMemQueue
      -- state_transition
      DirectoryState := Directory_I;
    else
        ErrorUnhandledMsg(msg);
    endswitch;
                
  case Directory_ID_W:
    switch etype
    case Directory_GETX:
      -- z_recycleRequestQueue
      msg_recycled := true;
      -- state_transition
      DirectoryState := Directory_ID_W;
    case Directory_GETS:
      -- z_recycleRequestQueue
      msg_recycled := true;
      -- state_transition
      DirectoryState := Directory_ID_W;
    case Directory_PUTX:
      -- z_recycleRequestQueue
      msg_recycled := true;
      -- state_transition
      DirectoryState := Directory_ID_W;
    case Directory_PUTX_NotOwner:
      -- z_recycleRequestQueue
      msg_recycled := true;
      -- state_transition
      DirectoryState := Directory_ID_W;
    case Directory_DMA_WRITE:
      -- y_recycleDMARequestQueue
      msg_recycled := true;
      -- state_transition
      DirectoryState := Directory_ID_W;
    case Directory_DMA_READ:
      -- y_recycleDMARequestQueue
      msg_recycled := true;
      -- state_transition
      DirectoryState := Directory_ID_W;
    case Directory_Memory_Ack:
      -- da_sendDMAAck
      Send(DMAResponseType_ACK, tbe.DmaRequestor, UNDEFINED, UNDEFINED, 1, UNDEFINED, UNDEFINED);
      -- w_deallocateTBE
      ResetDirectoryTBEEntry();
      -- l_popMemQueue
      -- state_transition
      DirectoryState := Directory_I;
    else
        ErrorUnhandledMsg(msg);
    endswitch;
                
  case Directory_I:
    switch etype
    case Directory_GETX:
      -- v_allocateTBEFromRequestNet
      ResetDirectoryTBEEntry();
      tbe.val := msg.val;
      -- qf_queueMemoryFetchRequest
      Send(MemoryRequestType_MEMORY_READ, MemoryType, DirectoryType, msg.req, 0, UNDEFINED, UNDEFINED);
      -- e_ownerIsRequestor
      DirectoryNode.owner:= msg.req;
      -- i_popIncomingRequestQueue
      -- state_transition
      DirectoryState := Directory_IM;
    case Directory_DMA_READ:
      -- r_allocateTbeForDmaRead
      tbe.DmaRequestor := msg.req;
      -- qf_queueMemoryFetchRequestDMA
      Send(MemoryRequestType_MEMORY_READ, MemoryType, DirectoryType, msg.req, 0, UNDEFINED, UNDEFINED);
      -- p_popIncomingDMARequestQueue
      -- state_transition
      DirectoryState := Directory_ID;
    case Directory_DMA_WRITE:
      -- v_allocateTBE
      ResetDirectoryTBEEntry();
      tbe.val := msg.val;
      tbe.DmaRequestor := msg.req;
      -- qw_queueMemoryWBRequest_partial
      Send(MemoryRequestType_MEMORY_WB, MemoryType, DirectoryType, msg.req, 0, msg.val, UNDEFINED);
      -- p_popIncomingDMARequestQueue
      -- state_transition
      DirectoryState := Directory_ID_W;
    case Directory_PUTX_NotOwner:
      -- b_sendWriteBackNack
      Send(CoherenceRequestType_WB_NACK, msg.req, DirectoryType, msg.req, 3, UNDEFINED, UNDEFINED);
      -- i_popIncomingRequestQueue
      -- state_transition
      DirectoryState := Directory_I;
    else
        ErrorUnhandledMsg(msg);
    endswitch;
                
  case Directory_M:
    switch etype
    case Directory_DMA_READ:
      -- v_allocateTBE
      ResetDirectoryTBEEntry();
      tbe.val := msg.val;
      tbe.DmaRequestor := msg.req;
      -- inv_sendCacheInvalidate
      Send(CoherenceRequestType_INV, DirectoryNode.owner, DirectoryType, msg.req, 3, UNDEFINED, UNDEFINED);
      -- p_popIncomingDMARequestQueue
      -- state_transition
      DirectoryState := Directory_M_DRD;
    case Directory_DMA_WRITE:
      -- v_allocateTBE
      ResetDirectoryTBEEntry();
      tbe.val := msg.val;
      tbe.DmaRequestor := msg.req;
      -- inv_sendCacheInvalidate
      Send(CoherenceRequestType_INV, DirectoryNode.owner, DirectoryType, msg.req, 3, UNDEFINED, UNDEFINED);
      -- p_popIncomingDMARequestQueue
      -- state_transition
      DirectoryState := Directory_M_DWR;
    case Directory_GETX:
      -- f_forwardRequest
      Send(msg.mtype, DirectoryNode.owner, DirectoryType, msg.req, 3, UNDEFINED, UNDEFINED);
      -- e_ownerIsRequestor
      DirectoryNode.owner:= msg.req;
      -- i_popIncomingRequestQueue
      -- state_transition
      DirectoryState := Directory_M;
    case Directory_PUTX:
      -- c_clearOwner
      undefine DirectoryNode.owner;
      -- v_allocateTBEFromRequestNet
      ResetDirectoryTBEEntry();
      tbe.val := msg.val;
      -- l_queueMemoryWBRequest
      Send(MemoryRequestType_MEMORY_WB, MemoryType, DirectoryType, msg.req, 0, msg.val, UNDEFINED);
      -- i_popIncomingRequestQueue
      -- state_transition
      DirectoryState := Directory_MI;
    case Directory_PUTX_NotOwner:
      -- b_sendWriteBackNack
      Send(CoherenceRequestType_WB_NACK, msg.req, DirectoryType, msg.req, 3, UNDEFINED, UNDEFINED);
      -- i_popIncomingRequestQueue
      -- state_transition
      DirectoryState := Directory_M;
    else
        ErrorUnhandledMsg(msg);
    endswitch;
                
  else
      ErrorUnhandledState();
  endswitch;
  endalias;
  endalias;
End;
        
---------------------------------------------------------------------------
-- DMA Communication
--------------------------------------------------------------------------

Procedure DMAReceive(msg: Message);
var cnt:0..L1CacheCount;   -- for counting sharers
var etype : EventType;   -- event type from peek
Begin
  cnt := MultiSetCount(i:DirectoryNode.sharers, true);
  alias tbe:DMATBENode do
  alias DMAState:DMANode.state do
  msg_processed :=  true;
  msg_recycled := false;
  etype := DMAPeek(msg);

  switch DMAState
  case DMA_READY:
    switch etype
    case DMA_ReadRequest:
      -- v_allocateTBE
      ResetDMATBEEntry();
      -- s_sendReadRequest
      Send(DMARequestType_READ, DirectoryType, DMAType, DMAType, 0, msg.val, UNDEFINED);
      -- p_popRequestQueue
      -- state_transition
      DMAState := DMA_BUSY_RD;
    case DMA_WriteRequest:
      -- v_allocateTBE
      ResetDMATBEEntry();
      -- s_sendWriteRequest
      Send(DMARequestType_WRITE, DirectoryType, DMAType, DMAType, 0, msg.val, UNDEFINED);
      -- p_popRequestQueue
      -- state_transition
      DMAState := DMA_BUSY_WR;
    else
        ErrorUnhandledMsg(msg);
    endswitch;
                
  case DMA_BUSY_RD:
    switch etype
    case DMA_Data:
      -- t_updateTBEData
      tbe.val := msg.val;
      -- d_dataCallback
      -- w_deallocateTBE
      ResetDMATBEEntry();
      -- p_popResponseQueue
      -- wkad_wakeUpAllDependents
      -- state_transition
      DMAState := DMA_READY;
    case DMA_ReadRequest:
      -- zz_stallAndWaitRequestQueue
      msg_processed := false;
      -- state_transition
      DMAState := DMA_BUSY_RD;
    case DMA_WriteRequest:
      -- zz_stallAndWaitRequestQueue
      msg_processed := false;
      -- state_transition
      DMAState := DMA_BUSY_RD;
    else
        ErrorUnhandledMsg(msg);
    endswitch;
                
  case DMA_BUSY_WR:
    switch etype
    case DMA_Ack:
      -- a_ackCallback
      -- w_deallocateTBE
      ResetDMATBEEntry();
      -- p_popResponseQueue
      -- wkad_wakeUpAllDependents
      -- state_transition
      DMAState := DMA_READY;
    case DMA_ReadRequest:
      -- zz_stallAndWaitRequestQueue
      msg_processed := false;
      -- state_transition
      DMAState := DMA_BUSY_WR;
    case DMA_WriteRequest:
      -- zz_stallAndWaitRequestQueue
      msg_processed := false;
      -- state_transition
      DMAState := DMA_BUSY_WR;
    else
        ErrorUnhandledMsg(msg);
    endswitch;
                
  else
      ErrorUnhandledState();
  endswitch;
  endalias;
  endalias;
End;
        
---------------------------------------------------------------------------
-- Cache Communication
--------------------------------------------------------------------------
    
Procedure L1CacheReceive(msg:Message; c:L1Cache);
    
var ncount : 0..L1CacheCount;                      --for counting total acks received
var etype : EventType;
Begin
  msg_processed := true;
  msg_recycled := false;
  etype := L1CachePeek(msg);
  
  alias L1CacheState:L1Caches[c].state do
  alias cv:L1Caches[c].val do
  alias cc:L1Caches[c].cnt do
  alias ct:L1Caches[c].totalacks do
  alias tbe:L1CacheTBEs[c] do
  switch L1CacheState
  case L1Cache_IS:
    switch etype
    case L1Cache_Load:
      -- z_stall
      msg_processed := false;
      -- state_transition
      L1CacheState := L1Cache_IS;
    case L1Cache_Ifetch:
      -- z_stall
      msg_processed := false;
      -- state_transition
      L1CacheState := L1Cache_IS;
    case L1Cache_Store:
      -- z_stall
      msg_processed := false;
      -- state_transition
      L1CacheState := L1Cache_IS;
    case L1Cache_Replacement:
      -- z_stall
      msg_processed := false;
      -- state_transition
      L1CacheState := L1Cache_IS;
    case L1Cache_Fwd_GETX:
      -- z_stall
      msg_processed := false;
      -- state_transition
      L1CacheState := L1Cache_IS;
    case L1Cache_Inv:
      -- z_stall
      msg_processed := false;
      -- state_transition
      L1CacheState := L1Cache_IS;
    case L1Cache_Data:
      -- u_writeDataToCache
      cv := msg.val;
      LastWrite := msg.val;
      -- rx_load_hit
      -- w_deallocateTBE
      ResetL1CacheTBEEntry(c);
      -- n_popResponseQueue
      -- state_transition
      L1CacheState := L1Cache_M;
    else
        ErrorUnhandledMsg(msg);
    endswitch;
                
  case L1Cache_IM:
    switch etype
    case L1Cache_Load:
      -- z_stall
      msg_processed := false;
      -- state_transition
      L1CacheState := L1Cache_IM;
    case L1Cache_Ifetch:
      -- z_stall
      msg_processed := false;
      -- state_transition
      L1CacheState := L1Cache_IM;
    case L1Cache_Store:
      -- z_stall
      msg_processed := false;
      -- state_transition
      L1CacheState := L1Cache_IM;
    case L1Cache_Replacement:
      -- z_stall
      msg_processed := false;
      -- state_transition
      L1CacheState := L1Cache_IM;
    case L1Cache_Fwd_GETX:
      -- z_stall
      msg_processed := false;
      -- state_transition
      L1CacheState := L1Cache_IM;
    case L1Cache_Inv:
      -- z_stall
      msg_processed := false;
      -- state_transition
      L1CacheState := L1Cache_IM;
    case L1Cache_Data:
      -- u_writeDataToCache
      cv := msg.val;
      LastWrite := msg.val;
      -- sx_store_hit
      cv := msg.val;
      LastWrite := msg.val;
      -- w_deallocateTBE
      ResetL1CacheTBEEntry(c);
      -- n_popResponseQueue
      -- state_transition
      L1CacheState := L1Cache_M;
    else
        ErrorUnhandledMsg(msg);
    endswitch;
                
  case L1Cache_MI:
    switch etype
    case L1Cache_Load:
      -- z_stall
      msg_processed := false;
      -- state_transition
      L1CacheState := L1Cache_MI;
    case L1Cache_Ifetch:
      -- z_stall
      msg_processed := false;
      -- state_transition
      L1CacheState := L1Cache_MI;
    case L1Cache_Store:
      -- z_stall
      msg_processed := false;
      -- state_transition
      L1CacheState := L1Cache_MI;
    case L1Cache_Replacement:
      -- z_stall
      msg_processed := false;
      -- state_transition
      L1CacheState := L1Cache_MI;
    case L1Cache_Inv:
      -- o_popForwardedRequestQueue
      -- state_transition
      L1CacheState := L1Cache_MI;
    case L1Cache_Writeback_Ack:
      -- w_deallocateTBE
      ResetL1CacheTBEEntry(c);
      -- o_popForwardedRequestQueue
      -- state_transition
      L1CacheState := L1Cache_I;
    case L1Cache_Fwd_GETX:
      -- ee_sendDataFromTBE
      Send(CoherenceResponseType_DATA, msg.req, c, msg.req, 4, tbe.val, UNDEFINED);
      -- o_popForwardedRequestQueue
      -- state_transition
      L1CacheState := L1Cache_II;
    case L1Cache_Writeback_Nack:
      -- o_popForwardedRequestQueue
      -- state_transition
      L1CacheState := L1Cache_MII;
    else
        ErrorUnhandledMsg(msg);
    endswitch;
                
  case L1Cache_II:
    switch etype
    case L1Cache_Load:
      -- z_stall
      msg_processed := false;
      -- state_transition
      L1CacheState := L1Cache_II;
    case L1Cache_Ifetch:
      -- z_stall
      msg_processed := false;
      -- state_transition
      L1CacheState := L1Cache_II;
    case L1Cache_Store:
      -- z_stall
      msg_processed := false;
      -- state_transition
      L1CacheState := L1Cache_II;
    case L1Cache_Replacement:
      -- z_stall
      msg_processed := false;
      -- state_transition
      L1CacheState := L1Cache_II;
    case L1Cache_Writeback_Ack:
      -- w_deallocateTBE
      ResetL1CacheTBEEntry(c);
      -- o_popForwardedRequestQueue
      -- state_transition
      L1CacheState := L1Cache_I;
    case L1Cache_Writeback_Nack:
      -- w_deallocateTBE
      ResetL1CacheTBEEntry(c);
      -- o_popForwardedRequestQueue
      -- state_transition
      L1CacheState := L1Cache_I;
    else
        ErrorUnhandledMsg(msg);
    endswitch;
                
  case L1Cache_MII:
    switch etype
    case L1Cache_Load:
      -- z_stall
      msg_processed := false;
      -- state_transition
      L1CacheState := L1Cache_MII;
    case L1Cache_Ifetch:
      -- z_stall
      msg_processed := false;
      -- state_transition
      L1CacheState := L1Cache_MII;
    case L1Cache_Store:
      -- z_stall
      msg_processed := false;
      -- state_transition
      L1CacheState := L1Cache_MII;
    case L1Cache_Replacement:
      -- z_stall
      msg_processed := false;
      -- state_transition
      L1CacheState := L1Cache_MII;
    case L1Cache_Fwd_GETX:
      -- ee_sendDataFromTBE
      Send(CoherenceResponseType_DATA, msg.req, c, msg.req, 4, tbe.val, UNDEFINED);
      -- w_deallocateTBE
      ResetL1CacheTBEEntry(c);
      -- o_popForwardedRequestQueue
      -- state_transition
      L1CacheState := L1Cache_I;
    else
        ErrorUnhandledMsg(msg);
    endswitch;
                
  case L1Cache_M:
    switch etype
    case L1Cache_Store:
      -- s_store_hit
      cv := msg.val;
      LastWrite := msg.val;
      -- p_profileHit
      -- m_popMandatoryQueue
      -- state_transition
      L1CacheState := L1Cache_M;
    case L1Cache_Load:
      -- r_load_hit
      -- p_profileHit
      -- m_popMandatoryQueue
      -- state_transition
      L1CacheState := L1Cache_M;
    case L1Cache_Ifetch:
      -- r_load_hit
      -- p_profileHit
      -- m_popMandatoryQueue
      -- state_transition
      L1CacheState := L1Cache_M;
    case L1Cache_Fwd_GETX:
      -- e_sendData
      Send(CoherenceResponseType_DATA, msg.req, c, msg.req, 4, cv, UNDEFINED);
      -- forward_eviction_to_cpu
      undefine cv;
      -- o_popForwardedRequestQueue
      -- state_transition
      L1CacheState := L1Cache_I;
    case L1Cache_Replacement:
      -- v_allocateTBE
      ResetL1CacheTBEEntry(c);
      -- b_issuePUT
      Send(CoherenceRequestType_PUTX, DirectoryType, c, c, 2, cv, UNDEFINED);
      -- x_copyDataFromCacheToTBE
      tbe.val := cv;
      -- forward_eviction_to_cpu
      undefine cv;
      -- h_deallocateL1CacheBlock
      ResetL1CacheEntry(c);
      -- state_transition
      L1CacheState := L1Cache_MI;
    case L1Cache_Inv:
      -- v_allocateTBE
      ResetL1CacheTBEEntry(c);
      -- b_issuePUT
      Send(CoherenceRequestType_PUTX, DirectoryType, c, c, 2, cv, UNDEFINED);
      -- x_copyDataFromCacheToTBE
      tbe.val := cv;
      -- forward_eviction_to_cpu
      undefine cv;
      -- h_deallocateL1CacheBlock
      ResetL1CacheEntry(c);
      -- state_transition
      L1CacheState := L1Cache_MI;
    else
        ErrorUnhandledMsg(msg);
    endswitch;
                
  case L1Cache_I:
    switch etype
    case L1Cache_Inv:
      -- o_popForwardedRequestQueue
      -- state_transition
      L1CacheState := L1Cache_I;
    case L1Cache_Store:
      -- v_allocateTBE
      ResetL1CacheTBEEntry(c);
      -- i_allocateL1CacheBlock
      ResetL1CacheEntry(c);
      -- a_issueRequest
      Send(CoherenceRequestType_GETX, DirectoryType, c, c, 2, UNDEFINED, UNDEFINED);
      -- p_profileMiss
      -- m_popMandatoryQueue
      -- state_transition
      L1CacheState := L1Cache_IM;
    case L1Cache_Load:
      -- v_allocateTBE
      ResetL1CacheTBEEntry(c);
      -- i_allocateL1CacheBlock
      ResetL1CacheEntry(c);
      -- a_issueRequest
      Send(CoherenceRequestType_GETX, DirectoryType, c, c, 2, UNDEFINED, UNDEFINED);
      -- p_profileMiss
      -- m_popMandatoryQueue
      -- state_transition
      L1CacheState := L1Cache_IS;
    case L1Cache_Ifetch:
      -- v_allocateTBE
      ResetL1CacheTBEEntry(c);
      -- i_allocateL1CacheBlock
      ResetL1CacheEntry(c);
      -- a_issueRequest
      Send(CoherenceRequestType_GETX, DirectoryType, c, c, 2, UNDEFINED, UNDEFINED);
      -- p_profileMiss
      -- m_popMandatoryQueue
      -- state_transition
      L1CacheState := L1Cache_IS;
    case L1Cache_Replacement:
      -- h_deallocateL1CacheBlock
      ResetL1CacheEntry(c);
      -- state_transition
      L1CacheState := L1Cache_I;
    else
        ErrorUnhandledMsg(msg);
    endswitch;
                
  else
      ErrorUnhandledState();

  endswitch;
  endalias;
  endalias;
  endalias;
  endalias;
  endalias;
End;
    
---------------------------------------------------------------------------
-- Memory Communication
--------------------------------------------------------------------------

Procedure MemoryReceive(msg: Message);
var etype : EventType;
Begin
  alias MemoryValue:MemoryNode.val do
  msg_processed :=  true;
  msg_recycled := false;

  etype := MemoryPeek(msg);

  switch etype
   case Memory_Read:
        Send(MemoryRequestType_MEMORY_READ, msg.src, MemoryType, msg.req, 0, MemoryValue, UNDEFINED);
   case Memory_WB:
        MemoryValue := msg.val;
        LastWrite := msg.val;
        Send(MemoryRequestType_MEMORY_WB, msg.src, MemoryType, msg.req, 0, UNDEFINED, UNDEFINED);
    else
        ErrorUnhandledMsg(msg);
    endswitch;
  endalias;
End;
---------------------------------------------------------------------------
-- Rules
---------------------------------------------------------------------------
-- Events from Core to L1Cache (challenge coherency)

ruleset c:L1Cache Do
  ruleset v:Value Do
  rule "store"
    isundefined(InBox[c][0].mtype)
    & MultiSetCount(i:Net[c], true) = 0
  ==>
    Send(RubyRequestType_ST, c, UNDEFINED, UNDEFINED, VC0, v, UNDEFINED);
  endrule;
  endruleset;

  rule "load"
    isundefined(InBox[c][0].mtype)
    & MultiSetCount(i:Net[c], true) = 0
  ==>
    Send(RubyRequestType_LD, c, UNDEFINED, UNDEFINED, VC0, UNDEFINED, UNDEFINED);
  endrule;

  rule "replacement"
    isundefined(InBox[c][0].mtype)
    & MultiSetCount(i:Net[c], true) = 0
  ==>
    Send(RubyRequestType_Replacement, c, UNDEFINED, UNDEFINED, VC0, UNDEFINED, UNDEFINED);
  endrule;

  rule "ifetch" --- we regard ifetch as load
    false & isundefined(InBox[c][0].mtype)
    & MultiSetCount(i:Net[c], true) = 0
  ==>
    Send(RubyRequestType_IFETCH, c, UNDEFINED, UNDEFINED, VC0, UNDEFINED, UNDEFINED);
  endrule;

endruleset;

-- Events to DMA (challenge coherency)

  ruleset v:Value Do
  rule "DMA store"
    isundefined(InBox[DMAType][0].mtype)
    & MultiSetCount(i:Net[DMAType], true) = 0
  ==>
    Send(SequencerRequestType_ST, DMAType, UNDEFINED, UNDEFINED, VC0, v, UNDEFINED);
  endrule;
  endruleset;

  rule "DMA load"
    isundefined(InBox[DMAType][0].mtype)
    & MultiSetCount(i:Net[DMAType], true) = 0
  ==>
    Send(SequencerRequestType_LD, DMAType, UNDEFINED, UNDEFINED, VC0, UNDEFINED, UNDEFINED);
  endrule;
--------------------------------------------------------------------------
-- Message delivery
--------------------------------------------------------------------------
ruleset n:Node do
  choose midx:Net[n] do
    alias chan:Net[n] do
    alias msg:chan[midx] do
    alias box:InBox[n] do
    -- Pick a random message in the network and deliver it 
    -- if there is no msg in the corresponding channel's inbox
    rule "receive-net"
			(isundefined(box[msg.vc].mtype))
    ==>
    if IsMember(n, Memory)
    then
        MemoryReceive(msg);
    else
        if IsMember(n, DMA)
        then
            DMAReceive(msg);
        else
            if IsMember(n, Directory)
            then
                DirectoryReceive(msg);
            else
                L1CacheReceive(msg, n);
            endif;
        endif;
    endif;


            Assert (msg_processed | !msg_recycled) "Messages cannot be blocked and recycled at the same time";

			if ! msg_processed
			then
			    -- The node refused the message, stick it in the InBox to block the VC and remove it from queue.
	  		    box[msg.vc] := msg;
	  		    MultiSetRemove(midx, chan);
	  		else
	  		    if msg_recycled
	  		    then
	  		        -- recycle the message queue.
	  		        -- we need do nothing
	  		    else
	  		        -- processed and not recycled, remove it from queue
	  		        MultiSetRemove(midx, chan);
	  		    endif;

			endif;


    endrule;

    endalias
    endalias;
    endalias;
  endchoose;

-- Try to deliver a message from a blocked VC; perhaps the node can handle it now
ruleset vc:VCType do
  rule "receive-blocked-vc"
    (! isundefined(InBox[n][vc].mtype))
  ==>
    if IsMember(n, Memory)
    then
        MemoryReceive(InBox[n][vc]);
    else
        if IsMember(n, DMA)
        then
            DMAReceive(InBox[n][vc]);
        else
            if IsMember(n, Directory)
            then
                DirectoryReceive(InBox[n][vc]);
            else
                L1CacheReceive(InBox[n][vc], n);
            endif;
        endif;
    endif;


    Assert (msg_processed | !msg_recycled) "Messages cannot be blocked and recycled at the same time";

    if msg_processed
    then
        if msg_recycled
        then
            -- put it back to queue
            MultiSetAdd(InBox[n][vc], Net[n]);
        endif;
      -- Message has been handled, forget it
      undefine InBox[n][vc];
    endif;

  endrule;
endruleset;

endruleset;
----------------------------------------------------------------------
-- Startstate
----------------------------------------------------------------------
startstate

  ResetDirectoryEntry();
  ResetDMAEntry();
  ResetDirectoryTBEEntry();
  ResetDMATBEEntry();
  DirectoryNode.state := Directory_I;
  DMANode.state := DMA_READY;
  

  For v:Value do
    MemoryNode.val := v;
  endfor;
  LastWrite := MemoryNode.val;

  -- cache node initialization
  for i:L1Cache do
    ResetL1CacheEntry(i);
    ResetL1CacheTBEEntry(i);
    L1Caches[i].state := L1Cache_I;
    L1Caches[i].cnt := 0;
    L1Caches[i].totalacks := L1CacheCount -1;
  endfor;

  -- network initialization
  undefine Net;

  msg_processed := true;
  msg_recycled := false;
endstartstate;
----------------------------------------------------------------------
-- Invariants
----------------------------------------------------------------------

invariant "Invalid implies empty owner"
  DirectoryNode.state = Directory_I
    ->
      IsUndefined(DirectoryNode.owner);

invariant "value in memory matches value of last write, when invalid"
     DirectoryNode.state = Directory_I
    ->
	 MemoryNode.val = LastWrite;

invariant "Invalid implies empty sharer list"
  DirectoryNode.state = Directory_I
    ->
      MultiSetCount(i:DirectoryNode.sharers, true) = 0;

invariant "invalid means value doesn't exist in cache"
  Forall n : L1Cache Do
     L1Caches[n].state = L1Cache_I
     ->
      IsUndefined(L1Caches[n].val)
  end;
