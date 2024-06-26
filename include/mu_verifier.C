/* -*- C++ -*-
 * mu_verifier.C
 * @(#) Main routines for the driver for Murphi verifiers.
 *
 * Copyright (C) 1992 - 1999 by the Board of Trustees of              
 * Leland Stanford Junior University.
 *
 * License to use, copy, modify, sell and/or distribute this software
 * and its documentation any purpose is hereby granted without royalty,
 * subject to the following terms and conditions:
 *
 * 1.  The above copyright notice and this permission notice must
 * appear in all copies of the software and related documentation.
 *
 * 2.  The name of Stanford University may not be used in advertising or
 * publicity pertaining to distribution of the software without the
 * specific, prior written permission of Stanford.
 *
 * 3.  This software may not be called "Murphi" if it has been modified
 * in any way, without the specific prior written permission of David L.
 * Dill.
 *
 * 4.  THE SOFTWARE IS PROVIDED "AS-IS" AND STANFORD MAKES NO
 * REPRESENTATIONS OR WARRANTIES, EXPRESS OR IMPLIED, BY WAY OF EXAMPLE,
 * BUT NOT LIMITATION.  STANFORD MAKES NO REPRESENTATIONS OR WARRANTIES
 * OF MERCHANTABILITY OR FITNESS FOR ANY PARTICULAR PURPOSE OR THAT THE
 * USE OF THE SOFTWARE WILL NOT INFRINGE ANY PATENTS, COPYRIGHTS
 * TRADEMARKS OR OTHER RIGHTS. STANFORD SHALL NOT BE LIABLE FOR ANY
 * LIABILITY OR DAMAGES WITH RESPECT TO ANY CLAIM BY LICENSEE OR ANY
 * THIRD PARTY ON ACCOUNT OF, OR ARISING FROM THE LICENSE, OR ANY
 * SUBLICENSE OR USE OF THE SOFTWARE OR ANY SERVICE OR SUPPORT.
 *
 * LICENSEE shall indemnify, hold harmless and defend STANFORD and its
 * trustees, officers, employees, students and agents against any and all
 * claims arising out of the exercise of any rights under this Agreement,
 * including, without limiting the generality of the foregoing, against
 * any damages, losses or liabilities whatsoever with respect to death or
 * injury to person or damage to property arising from or out of the
 * possession, use, or operation of Software or Licensed Program(s) by
 * LICENSEE or its customers.
 *
 * Read the file "license" distributed with these sources, or call
 * Murphi with the -l switch for additional information.
 * 
 */

/* 
 * Original Author: Ralph Melton
 * Extracted from mu_epilog.inc and mu_prolog.inc
 * by C. Norris Ip
 * Created: 21 April 93
 *
 * Update:
 *
 */

/****************************************
 There are 3 groups of implementations:
 None of them belong to any class
 1) verifying invariants
 2) transition sets generation
 3) verification and simulaiton supporting routines
 4) BFS algorithm supporting -- generate next stateset
 5) BFS algorithm main routine
 6) DFS algorithm main routine
 7) simulation
 8) global variables
 9) main function
 ****************************************/

/****************************************
 Global variables:
 void set_up_globals(int argc, char **argv)
 ****************************************/

// why exists? (Norris)
// saved value for the old new handler.
// void (*oldnh)() = NULL;       

#include <pthread.h>

/****************************************
 The Main() function:
 int main(int argc, char **argv)
 ****************************************/

static int g_initArgc;
static char** g_initArgv;

/* IM<b> */
void stats(int rules, unsigned long *res_ul, double *res_d, bool *res_b) {
	if (rules) {
		*res_ul = Rules->NumRulesFired();
		*res_d = Rules->NumRulesFired_d();
		*res_b = Rules->IsRulesFiredDouble();
	} else {
		*res_ul = StateSet->NumElts();
		*res_d = StateSet->NumElts_d();
		*res_b = StateSet->IsNumEltsDouble();
	}
}

int NotQueueEmpty() {
	return (int) (StateSet != NULL && !(StateSet->QueueIsEmpty()));
}

/* returns 1 if at least one new state is detected (should be always...) */
int addToLocalQueue(char* qline, int length) {
	if (StateSet == NULL)
		sched_yield(); /* worker, hurry up in creating... */
	return StateSet->AddMultiple(qline, length);
}
/* IM<e> */

/*
 * Patrick
 */
unsigned long getQueueSize() {
	if (StateSet == NULL)
		sched_yield(); /* worker, hurry up in creating... */

	return StateSet->QueueNumElts();
}

/**
 * Patrick
 */
void acceptPullRequest(int requesting_rank) {
	bool checked;
	unsigned long int numCurState;

	int numToSend = (int) sqrt(getQueueSize());
	LOG_VERBOSE(" (state) Sending %d states to node %d.\n", numToSend,
			requesting_rank);

	//TODO need to lock the queue

	for (int i = 0; i < numToSend; i++) {

		state *s = StateSet->QueueDequeue_Pull(checked, numCurState);
		if (!checked) {
			if (StateSet->SimpleWasPresent(curstate))
				continue;
		}
		Communicate->PushState((char*) s, requesting_rank);
	}
	Communicate->Flush(requesting_rank);

}

int g_argc;
char** g_argv;

//
// Have the comm thread perform all of the intializations.  This forces all MPI calls to be
// made from one thread.
//
void* startCommThread(void* syncMutex) {
	mutexes = new Mutexes(NUM_MUTEXES);
	Communicate = new commManager(&stats, &addToLocalQueue, &NotQueueEmpty,
			&getQueueSize, &acceptPullRequest, sizeof(class state),
			&g_initArgc, &g_initArgv);
	args = new argclass(g_initArgc, g_initArgv);
	

	CheckMemAvailable(args->bufsize.value, args->bufcount.value,
			args->mem.value);
	Communicate->InitializeCommQueues(args->bufcount.value, args->bufsize.value);
	Algorithm = new AlgorithmManager();

	/* signal worker to continue*/
	pthread_mutex_unlock((pthread_mutex_t*) syncMutex);

	/* Continue in comm loop */
	Communicate->StartThread();
	return NULL;
}

int main(int argc, char **argv) {
	pthread_attr_t commThreadAttr;
	pthread_mutex_t syncMutex;
	pthread_attr_init(&commThreadAttr);
	pthread_mutex_init(&syncMutex, NULL);

	g_initArgc = argc;
	g_initArgv = argv;

	pthread_mutex_lock(&syncMutex);
	pthread_create(commManager::GetThread(), &commThreadAttr, startCommThread,
			&syncMutex);

	/* wait until initializes finish */
	pthread_mutex_lock(&syncMutex);

	//   if ( args->debug_sym.value )
	//     {
	//       verify_bfs_standard();
	//       print_no_error();
	//       print_summary();
	//
	//       // copy_hashtable();
	//       debug_sym_the_states = new state_set;
	//       copy_state_set(debug_sym_the_states, the_states);
	//       the_states->clear_state_set();
	//
	//       args->symmetry_reduction.reset(TRUE);
	//       verify_bfs_standard();
	//       print_no_error();
	//       print_summary();
	//       if (args->print_hash.value)
	//      print_hashtable();
	//     }
	//   else
	if (args->main_alg.mode == argmain_alg::Verify_bfs) {
		Algorithm->verify_bfs();
	} else if (args->main_alg.mode == argmain_alg::Verify_dfs) {
		Algorithm->verify_dfs();
	} else if (args->main_alg.mode == argmain_alg::Simulate) {
		Algorithm->simulate();
	}

	cout.flush();
#ifdef HASHC
	/* IM<b> */
#ifdef HASHC_TRACE
	/* IM<e> */
	if (args->trace_file.value)
	delete TraceFile;
	/* IM<b> */
#endif
	/* IM<e> */
#endif
	if (Algorithm != NULL)
		delete Algorithm; //fix: begin destruction chain
	if (mutexes != NULL)
		delete mutexes;
	if (Communicate != NULL) {
		Communicate->DoBarrierAndFinalize();
		delete Communicate;
	}
	exit(0);
}

/****************************************
 * 8 Feb 94 Norris Ip:
 add print hashtable for debugging
 * 24 Feb 94 Norris Ip:
 added -debugsym option to run two hash tables in parallel
 for debugging purpose
 * 8 March 94 Norris Ip:
 merge with the latest rel2.6
 * 12 April 94 Norris Ip:
 add information about error in the condition of the rules
 category = CONDITION
 * 14 April 94 Norris Ip:
 fixed simlution mode printing when -h is used
 * 14 April 94 Norris Ip:
 change numbering of symmetry algorithms
 * 14 April 94 Norris Ip:
 fixed the number of digit in time output
 ****************************************/

/********************
 $Log: mu_verifier.C,v $

 Revision 2.0  2003/01/07 14:31:42  giuseppe
 added a call to delete in main() to delete Algorithm object

 Revision 1.2  1999/01/29 07:49:11  uli
 bugfixes

 Revision 1.4  1996/08/07 18:54:33  ip
 last bug fix on NextRule/SetNextEnabledRule has a bug; fixed this turn

 Revision 1.3  1996/08/07 01:00:18  ip
 Fixed bug on what_rule setting during guard evaluation; otherwise, bad diagnoistic message on undefine error on guard

 Revision 1.2  1996/08/07 00:15:26  ip
 fixed while code generation bug

 Revision 1.1  1996/08/07 00:14:46  ip
 Initial revision

 ********************/
