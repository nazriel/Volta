

#include <cstdio>

extern "C" void throwFunc(int i)
{
	throw i;
}

extern "C" void tryFunc(void (*foo)())
{
	try {
		foo();
	} catch (int i) {
		printf("C++: caught %i\n", i);
	}
}
