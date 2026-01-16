using System;

namespace ConfigGenerators.Sample
{
    class Program
    {
        static void Main(string[] args)
        {
            Console.WriteLine("Config Generators Sample Application");
            Console.WriteLine("=====================================");
            Console.WriteLine();
            Console.WriteLine("This project demonstrates the use of configuration attributes.");
            Console.WriteLine("When compiled, a 'configuration-metadata.json' file is generated");
            Console.WriteLine("containing all config entries and secrets for infrastructure provisioning.");
            Console.WriteLine();
            Console.WriteLine("Check the obj/Generated folder for the generated file.");
        }
    }
}
