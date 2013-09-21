// Most basic test.
module simple;


import core.stdc.stdio;
extern(C) void throwFunc(int i);
extern(C) void tryFunc(void function());

class MyException : Exception
{
	this()
	{
		super("my exception");
	}
}

void func1()
{
	try {
		printf("Volt: Calling throwing function\n".ptr);
		throwFunc(3);
	} catch (Exception t) {
		printf("Volt: cought %*s\n".ptr,
			cast(int)t.message.length,
			t.message.ptr);
	} finally {
		printf("Volt: finally\n".ptr);
	}
	return;
}

void func2()
{
	try {
		printf("Volt: Calling throwing function\n".ptr);
		throw new Exception("excepted");
	} catch (MyException t) {
		printf("Oh god!\n");
	} catch (Exception t) {
		printf("Volt: Exception %*s\n".ptr,
			cast(int)t.message.length,
			t.message.ptr);
	}
	return;
}

int main()
{
	printf("Volt: Calling try function\n".ptr);
	tryFunc(func1);
	printf("Volt: Back in main\n".ptr);
	printf("Volt: Calling try function\n".ptr);
	tryFunc(func2);
	printf("Volt: Back in main\n".ptr);
	return 42;
}
