//T compiles:yes
//T retval:42
//T dependency:m1.d
//T dependency:m4.d
//T has-passed:yes
// Constrained public imports.

module test_009;

import m4 : exportedVar;


int main()
{
	return exportedVar;
}
