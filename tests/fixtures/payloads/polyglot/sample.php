<?php
namespace Transmutation\Drivers;

use Exception;

class FileDriver {
    private $config;

    public function __construct(array $config) {
        $this->config = $config;
    }

    /**
     * @param string $path
     * @return bool
     */
    public function validate(string $path): bool {
        if (!file_exists($path)) {
            throw new Exception("File not found: " . $path);
        }
        return true;
    }
}