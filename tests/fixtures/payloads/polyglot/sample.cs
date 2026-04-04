using System;
using System.Threading.Tasks;

namespace Transmutation.Services {
    public interface IProcessor {
        Task<bool> RunAsync(string path);
    }

    public class LinuxProcessor : IProcessor {
        [LogAttribute]
        public async Task<bool> RunAsync(string path) {
            Console.WriteLine($"Running C# on {path}");
            await Task.Delay(10);
            return true;
        }
    }
}