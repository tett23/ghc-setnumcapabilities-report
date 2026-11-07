#include <pthread.h>
static pthread_mutex_t m = PTHREAD_MUTEX_INITIALIZER;
static int counter;
int locked_inc(int k) {
  pthread_mutex_lock(&m);
  int r = (counter += k);
  for (volatile int j = 0; j < 200; j++);
  pthread_mutex_unlock(&m);
  return r;
}
