<?php
/**
 * Plugin Name: Redis Object Cache (PHP 8+)
 * Description: Lightweight, high-performance drop-in object cache using Redis.
 * Version: 1.0.0
 * Author: Openbrige Inc, Thomas Spicer
 */

defined('ABSPATH') || exit; // Prevent direct file access.

if (!defined('WP_REDIS_DISABLED') || !WP_REDIS_DISABLED) :

/** ===========================================================================
 *                   PART 1: WordPress Function Definitions
 * ============================================================================
 * 
 * WordPress expects these `wp_cache_*()` functions to be globally defined. 
 * Do not rename or remove them, or the object cache will fail.
 */

/**
 * Check whether the object cache supports a feature.
 */
function wp_cache_supports(string $feature): bool {
    return match ($feature) {
        'add_multiple',
        'set_multiple',
        'get_multiple',
        'delete_multiple',
        'flush_runtime',
        'flush_group' => true,
        default => false,
    };
}

/**
 * Adds a value to cache if the key does not exist.
 *
 * @param string $key
 * @param mixed  $value
 * @param string $group
 * @param int    $expiration Number of seconds to store the value. 0 = permanent.
 */
function wp_cache_add(
    string $key, 
    mixed $value, 
    string $group = '', 
    int $expiration = 0
): bool {
    global $wp_object_cache;
    return $wp_object_cache->add($key, $value, $group, $expiration);
}

/**
 * Adds multiple values to cache in one call.
 */
function wp_cache_add_multiple(array $data, string $group = '', int $expire = 0): array {
    global $wp_object_cache;
    return $wp_object_cache->add_multiple($data, $group, $expire);
}

/**
 * Close the cache. (No-op)
 */
function wp_cache_close(): bool {
    return true;
}

/**
 * Decrement a numeric item's value.
 */
function wp_cache_decr(string $key, int $offset = 1, string $group = ''): int|bool {
    global $wp_object_cache;
    return $wp_object_cache->decrement($key, $offset, $group);
}

/**
 * Remove the item from the cache.
 */
function wp_cache_delete(string $key, string $group = '', int $time = 0): bool {
    global $wp_object_cache;
    return $wp_object_cache->delete($key, $group, $time);
}

/**
 * Deletes multiple values from the cache in one call.
 */
function wp_cache_delete_multiple(array $keys, string $group = ''): array {
    global $wp_object_cache;
    return $wp_object_cache->delete_multiple($keys, $group);
}

/**
 * Flush all cache. If WP_REDIS_SELECTIVE_FLUSH is set, flush only that prefix.
 */
function wp_cache_flush(): bool {
    global $wp_object_cache;
    return $wp_object_cache->flush();
}

/**
 * Removes all cache items in a group.
 */
function wp_cache_flush_group(string $group): bool {
    global $wp_object_cache;
    return $wp_object_cache->flush_group($group);
}

/**
 * Removes all items from the in-memory runtime cache only.
 */
function wp_cache_flush_runtime(): bool {
    global $wp_object_cache;
    return $wp_object_cache->flush_runtime();
}

/**
 * Retrieve an object from cache.
 */
function wp_cache_get(string $key, string $group = '', bool $force = false, ?bool &$found = null): mixed {
    global $wp_object_cache;
    return $wp_object_cache->get($key, $group, $force, $found);
}

/**
 * Retrieve multiple values from cache in one call.
 */
function wp_cache_get_multiple(array $keys, string $group = '', bool $force = false): array|false {
    global $wp_object_cache;
    return $wp_object_cache->get_multiple($keys, $group, $force);
}

/**
 * Increment a numeric item's value.
 */
function wp_cache_incr(string $key, int $offset = 1, string $group = ''): int|bool {
    global $wp_object_cache;
    return $wp_object_cache->increment($key, $offset, $group);
}

/**
 * Initialize the caching system and global $wp_object_cache.
 */
function wp_cache_init(): void {
    global $wp_object_cache;

    if (!defined('WP_REDIS_PREFIX') && getenv('WP_REDIS_PREFIX')) {
        define('WP_REDIS_PREFIX', getenv('WP_REDIS_PREFIX'));
    }

    if (!defined('WP_REDIS_SELECTIVE_FLUSH') && getenv('WP_REDIS_SELECTIVE_FLUSH')) {
        define('WP_REDIS_SELECTIVE_FLUSH', (bool) getenv('WP_REDIS_SELECTIVE_FLUSH'));
    }

    // Optional: WP_CACHE_KEY_SALT → WP_REDIS_PREFIX
    if (defined('WP_CACHE_KEY_SALT') && !defined('WP_REDIS_PREFIX')) {
        define('WP_REDIS_PREFIX', WP_CACHE_KEY_SALT);
    }

    if (!($wp_object_cache instanceof WP_Object_Cache)) {
        $fail_gracefully = defined('WP_REDIS_GRACEFUL') && WP_REDIS_GRACEFUL;
        $wp_object_cache = new WP_Object_Cache($fail_gracefully);
    }
}

/**
 * Replace a value in cache if the key already exists.
 */
function wp_cache_replace(string $key, mixed $value, string $group = '', int $expiration = 0): bool {
    global $wp_object_cache;
    return $wp_object_cache->replace($key, $value, $group, $expiration);
}

/**
 * Set a value in cache (unconditionally).
 */
function wp_cache_set(string $key, mixed $value, string $group = '', int $expiration = 0): bool {
    global $wp_object_cache;
    return $wp_object_cache->set($key, $value, $group, $expiration);
}

/**
 * Set multiple values to cache in one call.
 */
function wp_cache_set_multiple(array $data, string $group = '', int $expire = 0): array {
    global $wp_object_cache;
    return $wp_object_cache->set_multiple($data, $group, $expire);
}

/**
 * Switch blog (multisite).
 */
function wp_cache_switch_to_blog(int $_blog_id): bool {
    global $wp_object_cache;
    return $wp_object_cache->switch_to_blog($_blog_id);
}

/**
 * Make some groups global across sites.
 */
function wp_cache_add_global_groups(array|string $groups): void {
    global $wp_object_cache;
    $wp_object_cache->add_global_groups($groups);
}

/**
 * Exclude certain groups from saving to Redis.
 */
function wp_cache_add_non_persistent_groups(array|string $groups): void {
    global $wp_object_cache;
    $wp_object_cache->add_non_persistent_groups($groups);
}

/** ===========================================================================
 *                   PART 2: The WP_Object_Cache Class
 * ============================================================================
 */
class WP_Object_Cache {

    /**
     * -----------------------------------------------------------------------
     * Required Properties
     * -----------------------------------------------------------------------
     */
    // Declare prefix_cache at the top of your class properties:
    private array $prefix_cache = [];
    private int $max_runtime_entries = 1000;
    private array $cache = [];
    private \SplQueue $cacheEvictionQueue; // For eviction ordering of keys
    private bool $redis_connected = false;
    private bool $fail_gracefully = false;
    private array $errors = [];
    private array $global_groups = [];
    private array $ignored_groups = [];
    private array $unflushable_groups = [];
    private string|int $blog_prefix = 1;
    private string $global_prefix = 'global';
    private array $group_type = [];
    private array $diagnostics = [];
    private ?\Redis $redis = null;       // or \Relay\Relay or \Predis\Client at runtime
    private ?string $redis_version = null;
    private int $cache_hits = 0;
    private int $cache_misses = 0;
    private int $cache_calls = 0;
    private float $cache_time = 0.0;

    /**
     * Compression-Related Properties
     */

    private const COMPRESSION_PREFIX = 'C:';
    private const COMPRESSION_ZLIB_PREFIX = 'Z:';
    private const COMPRESSION_GZIP_PREFIX = 'G:';
    private array $compression_stats = [];

    private $runtime_lock;
    private const LOCK_TIMEOUT = 0.5; // 500ms timeout
    private array $cache_usage_tracking = [];
    private int $last_cleanup_time = 0;
    private const CLEANUP_INTERVAL = 3600; // 1 hour

    private const MAX_DB_SWITCH_RETRIES = 3;
    private array $db_switch_failures = [];
    private ?int $fallback_database = null;

    private bool $compression_enabled = true;
    private int $min_compress_length = 1024;
    private int $compression_level = 6;    // gzip compression level (1-9)
    private string $preferred_compression = 'gzip';

    private array $preload_keys = [];

    private const SCAN_COUNT = 1000;
    private const MAX_PIPELINE_SIZE = 100;
    private const FLUSH_BATCH_SIZE = 1000;
    private const MAX_FLUSH_ATTEMPTS = 3;
    private array $flush_stats = [];

    private const MAX_SERIALIZED_LENGTH = 64 * 1024 * 1024; // 64MB
    private const SERIALIZED_PATTERN = '/^((s|i|d|b|a|O|C|r|R|N):|{.*}$)/';
    private array $serialization_stats = [];

    private function attempt_reconnect(int $retries = 3, int $delay = 1): bool {
        for ($i = 0; $i < $retries; $i++) {
            try {
                if ($i > 0) {
                    sleep($delay); // Wait before retry
                }
                
                // Rebuild connection based on original parameters
                $client = $this->determine_client();
                $params = $this->build_parameters();
                
                switch ($client) {
                    case 'phpredis':
                        $this->connect_phpredis($params);
                        break;
                    case 'relay':
                        $this->connect_relay($params);
                        break;
                    default:
                        $this->connect_predis($params);
                }
                
                // Verify connection
                $this->redis->ping();
                $this->redis_connected = true;
                $this->fetch_info();
                
                // Restore original database if needed
                if ($this->current_database !== null) {
                    $this->redis->select($this->current_database);
                }
                
                return true;
                
            } catch (\Exception $e) {
                continue; // Try next iteration
            }
        }
        return false;
    }

    /**
     * Check if compression should be used for this value
     */
    private function should_compress(string $data): bool {
        // Check for existing compression markers
        if (str_starts_with($data, self::COMPRESSION_PREFIX) ||
            str_starts_with($data, self::COMPRESSION_ZLIB_PREFIX) ||
            str_starts_with($data, self::COMPRESSION_GZIP_PREFIX)) {
            return false;
        }
        
        // Don't compress small numeric values
        if (is_numeric($data) && strlen($data) < 20) {
            return false;
        }
        
        // Don't compress already compressed data formats
        $compressed_formats = [
            // Images
            "\x89\x50\x4E\x47", // PNG
            "\xFF\xD8\xFF",     // JPEG
            "\x1F\x8B\x08",     // GZIP
            "\x42\x5A\x68",     // BZIP2
            // Add more signatures as needed
        ];
        
        foreach ($compressed_formats as $signature) {
            if (str_starts_with($data, $signature)) {
                return false;
            }
        }
        
        return $this->compression_enabled &&
               strlen($data) >= $this->min_compress_length &&
               $this->get_compression_function() !== null;
    }
    
    // Add this new method to get appropriate compression function
    private function get_compression_function(): ?string {
        switch ($this->preferred_compression) {
            case 'gzip':
                if (function_exists('gzcompress')) {
                    return 'gzcompress';
                }
                // Fall through to zlib
                
            case 'zlib':
                if (function_exists('zlib_encode')) {
                    return 'zlib_encode';
                }
                break;
                
            case 'none':
                return null;
        }
        
        // Final fallback check
        if (function_exists('gzcompress')) {
            return 'gzcompress';
        }
        
        return null;
    }
    /**
     * Possibly unserialize and decompress data
     */
    private function maybe_serialize(mixed $value): string|false {
        try {
            $serialized = serialize($value);
            
            if (!$this->should_compress($serialized)) {
                return $serialized;
            }
            
            $compression_func = $this->get_compression_function();
            if ($compression_func === null) {
                return $serialized;
            }
            
            $before_size = strlen($serialized);
            $compressed = match($compression_func) {
                'gzcompress' => gzcompress($serialized, $this->compression_level),
                'zlib_encode' => zlib_encode($serialized, ZLIB_ENCODING_DEFLATE, $this->compression_level),
                default => false
            };
            
            if ($compressed === false) {
                error_log('Redis Cache: Compression failed');
                return $serialized;
            }
            
            $after_size = strlen($compressed);
            
            // Only use compression if it actually helps
            if ($after_size >= $before_size) {
                $this->track_compression_stats('skipped', $before_size);
                return $serialized;
            }
            
            $this->track_compression_stats('compressed', $before_size, $after_size);
            
            $prefix = match($compression_func) {
                'gzcompress' => self::COMPRESSION_GZIP_PREFIX,
                'zlib_encode' => self::COMPRESSION_ZLIB_PREFIX,
                default => self::COMPRESSION_PREFIX
            };
            
            return $prefix . $compressed;
            
        } catch (\Exception $e) {
            error_log('Redis Cache: Serialization error - ' . $e->getMessage());
            return false;
        }
    }
    
    // Replace maybe_unserialize method
    private function maybe_unserialize(mixed $data): mixed {
        if (!is_string($data)) {
            return $data;
        }
        
        try {
            // Check for compression prefixes
            $decompressed = null;
            
            if (str_starts_with($data, self::COMPRESSION_GZIP_PREFIX)) {
                if (!function_exists('gzuncompress')) {
                    throw new \RuntimeException('gzuncompress function not available');
                }
                $decompressed = gzuncompress(substr($data, strlen(self::COMPRESSION_GZIP_PREFIX)));
            } 
            elseif (str_starts_with($data, self::COMPRESSION_ZLIB_PREFIX)) {
                if (!function_exists('zlib_decode')) {
                    throw new \RuntimeException('zlib_decode function not available');
                }
                $decompressed = zlib_decode(substr($data, strlen(self::COMPRESSION_ZLIB_PREFIX)));
            }
            elseif (str_starts_with($data, self::COMPRESSION_PREFIX)) {
                // Legacy compression support
                if (!function_exists('gzuncompress')) {
                    throw new \RuntimeException('gzuncompress function not available');
                }
                $decompressed = gzuncompress(substr($data, strlen(self::COMPRESSION_PREFIX)));
            }
            
            if ($decompressed !== null) {
                if ($decompressed === false) {
                    throw new \RuntimeException('Decompression failed');
                }
                $data = $decompressed;
            }
            
            $unserialized = @unserialize($data);
            if ($unserialized === false && $data !== 'b:0;') {
                throw new \RuntimeException('Unserialization failed');
            }
            
            return $unserialized;
            
        } catch (\Exception $e) {
            error_log('Redis Cache: Unserialization error - ' . $e->getMessage());
            return false;
        }
    }

    private function track_compression_stats(string $type, int $before_size, ?int $after_size = null): void {
        if (!isset($this->compression_stats[$type])) {
            $this->compression_stats[$type] = [
                'count' => 0,
                'total_before' => 0,
                'total_after' => 0
            ];
        }
        
        $this->compression_stats[$type]['count']++;
        $this->compression_stats[$type]['total_before'] += $before_size;
        
        if ($after_size !== null) {
            $this->compression_stats[$type]['total_after'] += $after_size;
        }
    }
    
    // Add method to get compression statistics
    public function get_compression_stats(): array {
        $stats = $this->compression_stats;
        
        // Calculate ratios
        foreach ($stats as $type => $data) {
            if (isset($data['total_after']) && $data['total_before'] > 0) {
                $stats[$type]['ratio'] = round(
                    ($data['total_before'] - $data['total_after']) / $data['total_before'] * 100,
                    2
                );
            }
        }
        
        return $stats;
    }

    /**
     * Configure compression at runtime.
     */
    public function configure_compression(bool $enabled = true, int $min_length = 1024, int $level = 6): void {
        $this->compression_enabled = $enabled;
        $this->min_compress_length = $min_length;
        $this->compression_level   = max(1, min(9, $level));
    }

    /**
     * Constructor
     */
    public function __construct(bool $fail_gracefully = false) {
        $this->fail_gracefully = $fail_gracefully;
        $this->cacheEvictionQueue = new \SplQueue();

        // Determine the appropriate client, build parameters, then connect
        $client = $this->determine_client();
        $params = $this->build_parameters();

        try {
            switch ($client) {
                case 'phpredis':
                    $this->connect_phpredis($params);
                    break;
                case 'relay':
                    $this->connect_relay($params);
                    break;
                default:
                    // fallback to predis
                    $this->connect_predis($params);
            }
            $this->redis_connected = true;
            $this->fetch_info();

            // Add serializer configuration here, after connection is established
            $this->configure_serializer();

        } catch (\Exception $e) {
            $this->handle_exception($e);
        }

        // Initialize group lists (global, ignored, unflushable)
        $this->bootstrap_group_lists();
        $this->cache_group_types();

        // Configure compression from constants
        $compression_enabled   = defined('WP_REDIS_COMPRESSION') ? WP_REDIS_COMPRESSION : true;
        $min_compress_length   = defined('WP_REDIS_MIN_COMPRESS_LENGTH') ? (int)WP_REDIS_MIN_COMPRESS_LENGTH : 1024;
        $compression_level     = defined('WP_REDIS_COMPRESSION_LEVEL') ? (int)WP_REDIS_COMPRESSION_LEVEL : 6;
        $this->configure_compression($compression_enabled, $min_compress_length, $compression_level);

        $this->preload_cache();

        // Initialize the mutex
        if (class_exists('\SplMutex')) {
            $this->runtime_lock = new \SplMutex();
        } elseif (function_exists('sem_get') && function_exists('ftok')) {
            $this->runtime_lock = @sem_get(ftok(__FILE__, 'R'));
            if ($this->runtime_lock === false) {
                $this->runtime_lock = null;
            }
        } else {
            $this->runtime_lock = null;
        }

    }

    private function decompress_data(string $data): string|false {
        try {
            if (str_starts_with($data, self::COMPRESSION_GZIP_PREFIX)) {
                if (!function_exists('gzuncompress')) {
                    throw new \RuntimeException('gzuncompress function not available');
                }
                return gzuncompress(substr($data, strlen(self::COMPRESSION_GZIP_PREFIX)));
            }
            
            if (str_starts_with($data, self::COMPRESSION_ZLIB_PREFIX)) {
                if (!function_exists('zlib_decode')) {
                    throw new \RuntimeException('zlib_decode function not available');
                }
                return zlib_decode(substr($data, strlen(self::COMPRESSION_ZLIB_PREFIX)));
            }
            
            if (str_starts_with($data, self::COMPRESSION_PREFIX)) {
                if (!function_exists('gzuncompress')) {
                    throw new \RuntimeException('gzuncompress function not available');
                }
                return gzuncompress(substr($data, strlen(self::COMPRESSION_PREFIX)));
            }
            
            return false;
        } catch (\Exception $e) {
            error_log('Redis Cache: Decompression error - ' . $e->getMessage());
            return false;
        }
    }
    /**
     * Configure Redis serializer based on available extensions and settings
     */
    private function configure_serializer(): void {
        if (!$this->redis_status()) {
            return;
        }

        // Get configured serializer from constant or default to PHP
        $serializer = defined('WP_REDIS_SERIALIZER') 
            ? strtolower(WP_REDIS_SERIALIZER) 
            : 'php';

        try {
            switch ($serializer) {
                case 'igbinary':
                    if (extension_loaded('igbinary') && defined('Redis::SERIALIZER_IGBINARY')) {
                        $this->redis->setOption(\Redis::OPT_SERIALIZER, \Redis::SERIALIZER_IGBINARY);
                        $this->diagnostics['serializer'] = 'igbinary';
                    } else {
                        $this->fallback_to_php_serializer();
                    }
                    break;

                case 'json':
                    if (defined('Redis::SERIALIZER_JSON')) {
                        $this->redis->setOption(\Redis::OPT_SERIALIZER, \Redis::SERIALIZER_JSON);
                        $this->diagnostics['serializer'] = 'json';
                    } else {
                        $this->fallback_to_php_serializer();
                    }
                    break;

                case 'msgpack':
                    if (extension_loaded('msgpack') && defined('Redis::SERIALIZER_MSGPACK')) {
                        $this->redis->setOption(\Redis::OPT_SERIALIZER, \Redis::SERIALIZER_MSGPACK);
                        $this->diagnostics['serializer'] = 'msgpack';
                    } else {
                        $this->fallback_to_php_serializer();
                    }
                    break;

                case 'none':
                    if (defined('Redis::SERIALIZER_NONE')) {
                        $this->redis->setOption(\Redis::OPT_SERIALIZER, \Redis::SERIALIZER_NONE);
                        $this->diagnostics['serializer'] = 'none';
                    } else {
                        $this->fallback_to_php_serializer();
                    }
                    break;

                case 'php':
                default:
                    $this->fallback_to_php_serializer();
                    break;
            }
        } catch (\Exception $e) {
            error_log('Redis Cache: Error configuring serializer: ' . $e->getMessage());
            $this->fallback_to_php_serializer();
        }
    }

    /**
     * Set PHP as the fallback serializer
     */
    private function fallback_to_php_serializer(): void {
        try {
            if (defined('Redis::OPT_SERIALIZER') && defined('Redis::SERIALIZER_PHP')) {
                $this->redis->setOption(\Redis::OPT_SERIALIZER, \Redis::SERIALIZER_PHP);
                $this->diagnostics['serializer'] = 'php';
            }
        } catch (\Exception $e) {
            error_log('Redis Cache: Failed to set PHP serializer - ' . $e->getMessage());
        }
    }
    /**
     * Store a value in the runtime cache with eviction logic.
     */
    private function store_in_runtime_cache(string $derivedKey, mixed $value): void {
        try {
            if ($this->acquire_lock()) {
                try {
                    // Track memory usage before addition
                    $initial_memory = memory_get_usage();
                    
                    // Update existing entry
                    if (isset($this->cache[$derivedKey])) {
                        $this->cache[$derivedKey] = is_object($value) ? clone $value : $value;
                        $this->cache_usage_tracking[$derivedKey] = [
                            'time' => time(),
                            'size' => memory_get_usage() - $initial_memory
                        ];
                        return;
                    }

                    // Check memory limit before adding new entry
                    if ($this->check_memory_limit()) {
                        $this->force_cleanup();
                    }

                    // If still at capacity after cleanup, evict oldest
                    if ($this->cacheEvictionQueue->count() >= $this->max_runtime_entries) {
                        $this->evict_oldest();
                    }

                    // Add new entry
                    $this->cache[$derivedKey] = is_object($value) ? clone $value : $value;
                    $this->cacheEvictionQueue->enqueue($derivedKey);
                    
                    // Track memory usage
                    $this->cache_usage_tracking[$derivedKey] = [
                        'time' => time(),
                        'size' => memory_get_usage() - $initial_memory
                    ];

                    // Periodic cleanup check
                    $this->maybe_run_cleanup();
                    
                } finally {
                    $this->release_lock();
                }
            }
        } catch (\Exception $e) {
            error_log('Redis Cache: Runtime cache error: ' . $e->getMessage());
            // Emergency cleanup if something goes wrong
            $this->emergency_cleanup();
        }
    }

    // Add these new methods for memory management
    private function check_memory_limit(): bool {
        $limit = ini_get('memory_limit');
        if ($limit === '-1') return false; // No limit set
        
        $limit_bytes = $this->convert_to_bytes($limit);
        $current_usage = memory_get_usage();
        
        return ($current_usage / $limit_bytes) > 0.9; // 90% threshold
    }

    private function convert_to_bytes(string $value): int {
        $value = trim($value);
        $last = strtolower($value[strlen($value)-1]);
        $value = (int)$value;
        
        switch($last) {
            case 'g': $value *= 1024;
            case 'm': $value *= 1024;
            case 'k': $value *= 1024;
        }
        
        return $value;
    }

    private function force_cleanup(): void {
        // Remove entries exceeding age threshold
        $threshold = time() - 3600; // 1 hour old
        foreach ($this->cache_usage_tracking as $key => $data) {
            if ($data['time'] < $threshold) {
                $this->evict_key($key);
            }
        }
        
        // If still need more space, remove largest entries
        if ($this->check_memory_limit()) {
            uasort($this->cache_usage_tracking, fn($a, $b) => $b['size'] - $a['size']);
            $count = 0;
            foreach ($this->cache_usage_tracking as $key => $data) {
                $this->evict_key($key);
                $count++;
                if ($count >= 10) break; // Remove top 10 largest entries
            }
        }
    }

    private function evict_key(string $key): void {
        unset($this->cache[$key]);
        unset($this->cache_usage_tracking[$key]);
        
        // Requeue remaining items to maintain sync
        $temp_queue = new \SplQueue();
        while (!$this->cacheEvictionQueue->isEmpty()) {
            $qkey = $this->cacheEvictionQueue->dequeue();
            if ($qkey !== $key && isset($this->cache[$qkey])) {
                $temp_queue->enqueue($qkey);
            }
        }
        $this->cacheEvictionQueue = $temp_queue;
    }

    private function evict_oldest(): void {
        while (!$this->cacheEvictionQueue->isEmpty()) {
            $oldest_key = $this->cacheEvictionQueue->dequeue();
            if (isset($this->cache[$oldest_key])) {
                $this->evict_key($oldest_key);
                break;
            }
        }
    }

    private function maybe_run_cleanup(): void {
        $current_time = time();
        if (($current_time - $this->last_cleanup_time) >= self::CLEANUP_INTERVAL) {
            $this->force_cleanup();
            $this->last_cleanup_time = $current_time;
        }
    }

    private function emergency_cleanup(): void {
        try {
            // Reset everything in emergency
            $this->cache = [];
            $this->cache_usage_tracking = [];
            $this->cacheEvictionQueue = new \SplQueue();
            $this->last_cleanup_time = time();
            
            error_log('Redis Cache: Emergency cleanup performed');
        } catch (\Exception $e) {
            error_log('Redis Cache: Emergency cleanup failed: ' . $e->getMessage());
        }
    }
        
    // Add these new methods for lock handling
    private function acquire_lock(): bool {
        if ($this->runtime_lock === null) {
            return true; // No locking available, proceed anyway
        }
        
        if ($this->runtime_lock instanceof \SplMutex) {
            return $this->runtime_lock->lock();
        }
        
        return @sem_acquire($this->runtime_lock, true);
    }
    
    private function release_lock(): void {
        if ($this->runtime_lock === null) {
            return; // No locking available
        }
        
        if ($this->runtime_lock instanceof \SplMutex) {
            $this->runtime_lock->unlock();
            return;
        }
        
        @sem_release($this->runtime_lock);
    }
    
    // Add a destructor to ensure lock cleanup
    public function __destruct() {
        try {
            if ($this->redis) {
                $this->redis->close();
            }
            
            if ($this->runtime_lock instanceof \SplMutex) {
                if ($this->runtime_lock->locked()) {
                    $this->runtime_lock->unlock();
                }
            } elseif ($this->runtime_lock !== null) {
                @sem_remove($this->runtime_lock);
            }
        } catch (\Exception $e) {
            error_log('Redis Cache: Error cleaning up - ' . $e->getMessage());
        }
    }


    /**
     * Add keys to be preloaded on initialization
     */
    public function add_preload_keys(array $keys, string $group = 'default'): void {
        foreach ($keys as $key) {
            $this->preload_keys[] = $this->build_key($key, $group);
        }
    }

    /**
     * Preload frequently accessed keys into runtime cache
     */
    private function preload_cache(): void {
        if (empty($this->preload_keys) || !$this->redis_status()) {
            return;
        }
        
        try {
            $values = $this->redis->mget($this->preload_keys);
            if (!is_array($values)) {
                // If mget fails but doesn't throw, log and return
                error_log('WordPress Redis Cache: Failed to preload cache - invalid mget response');
                return;
            }
            
            foreach ($this->preload_keys as $i => $key) {
                if (isset($values[$i]) && $values[$i] !== false && $values[$i] !== null) {
                    $value = $this->maybe_unserialize($values[$i]);
                    if ($value !== false) {
                        $this->cache[$key] = $value;
                    }
                }
            }
        } catch (\Exception $e) {
            $this->handle_exception($e);
            return;
        }
    }

    /**
     * Initialize group arrays from possible user constants.
     */
    private function bootstrap_group_lists(): void {
        if (defined('WP_REDIS_GLOBAL_GROUPS') && is_array(WP_REDIS_GLOBAL_GROUPS)) {
            $this->global_groups = array_map([$this, 'sanitize_key_part'], WP_REDIS_GLOBAL_GROUPS);
        }
        $this->global_groups[] = 'redis-cache';

        if (defined('WP_REDIS_IGNORED_GROUPS') && is_array(WP_REDIS_IGNORED_GROUPS)) {
            $this->ignored_groups = array_map([$this, 'sanitize_key_part'], WP_REDIS_IGNORED_GROUPS);
        }

        if (defined('WP_REDIS_UNFLUSHABLE_GROUPS') && is_array(WP_REDIS_UNFLUSHABLE_GROUPS)) {
            $this->unflushable_groups = array_map([$this, 'sanitize_key_part'], WP_REDIS_UNFLUSHABLE_GROUPS);
        }
    }

    /**
     * Map each group into a "type" for quick checking later.
     */
    private function cache_group_types(): void {
        foreach ($this->global_groups as $g) {
            $this->group_type[$g] = 'global';
        }
        foreach ($this->ignored_groups as $g) {
            $this->group_type[$g] = 'ignored';
        }
        foreach ($this->unflushable_groups as $g) {
            $this->group_type[$g] = 'unflushable';
        }
    }

    /**
     * Determine which Redis client to use: phpredis, relay, or predis.
     */
    private function determine_client(): string {
        $client = 'predis';
        if (class_exists('Redis')) {
            $client = 'phpredis';
        }
        if (defined('WP_REDIS_CLIENT')) {
            $client = strtolower((string) WP_REDIS_CLIENT);
            // 'pecl' is often used to refer to phpredis in some docs
            $client = str_replace('pecl', 'phpredis', $client);
        }
        // If "relay" is configured but Relay extension isn't actually installed, fall back
        if ($client === 'relay' && !class_exists('\Relay\Relay')) {
            $client = 'phpredis';
        }
        return $client;
    }

    /**
     * Build connection parameters from constants or defaults.
     */
    private function build_parameters(): array {
        $default = [
            'scheme'         => 'tcp',
            'host'           => defined('WP_REDIS_HOST') ? WP_REDIS_HOST : '127.0.0.1',
            'port'           => defined('WP_REDIS_PORT') ? WP_REDIS_PORT : 6379,
            'database'       => defined('WP_REDIS_DATABASE') ? WP_REDIS_DATABASE : 0,
            'timeout'        => defined('WP_REDIS_TIMEOUT') ? WP_REDIS_TIMEOUT : 1,
            'read_timeout'   => defined('WP_REDIS_READ_TIMEOUT') ? WP_REDIS_READ_TIMEOUT : 1,
            'retry_interval' => defined('WP_REDIS_RETRY_INTERVAL') ? WP_REDIS_RETRY_INTERVAL : null,
            'persistent'     => defined('WP_REDIS_PERSISTENT') ? WP_REDIS_PERSISTENT : true, // Enable by default
            'persistent_id'  => defined('WP_REDIS_PERSISTENT_ID') ? WP_REDIS_PERSISTENT_ID : null,
            'password'       => null,
        ];

        // Map WP_REDIS_* constants into $default if defined
        foreach (['scheme','host','port','path','password','database','timeout','read_timeout','retry_interval'] as $setting) {
            $constant = 'WP_REDIS_' . strtoupper($setting);
            if (defined($constant)) {
                $default[$setting] = constant($constant);
            }
        }

        // If password is an empty string, remove it
        if (isset($default['password']) && $default['password'] === '') {
            unset($default['password']);
        }

        // Save some diagnostics
        $this->diagnostics['timeout']        = $default['timeout'];
        $this->diagnostics['read_timeout']   = $default['read_timeout'];
        $this->diagnostics['retry_interval'] = $default['retry_interval'];

        return $default;
    }

    /**
     * Connect using PhpRedis extension (PHP 8+ version).
     * 
     * @throws \RedisException If connection fails
     */
    private function connect_phpredis(array $params): void {
        $ver = \phpversion('redis');
        $this->diagnostics['client'] = "PhpRedis (v{$ver})";
        $this->redis = new \Redis();
    
        // Determine connection parameters based on scheme
        $host = strcasecmp($params['scheme'], 'unix') === 0 ? $params['path'] : $params['host'];
        $port = strcasecmp($params['scheme'], 'unix') === 0 ? 0 : (int) $params['port'];
    
        try {
            if ($params['persistent']) {
                $this->redis->pconnect(
                    $host,
                    $port,
                    (float) $params['timeout'],
                    $params['persistent_id'] ?? null,
                    (int) ($params['retry_interval'] ?? 0)
                );
            } else {
                $this->redis->connect(
                    $host,
                    $port,
                    (float) $params['timeout'],
                    null,
                    (int) ($params['retry_interval'] ?? 0)
                );
            }
    
            // Authentication
            if (!empty($params['password'])) {
                if (str_contains($params['password'], ',')) {
                    [$username, $password] = explode(',', $params['password'], 2);
                    $this->redis->auth(['user' => $username, 'pass' => $password]);
                } else {
                    $this->redis->auth($params['password']);
                }
            }
    
            // Select database
            if (!empty($params['database'])) {
                $this->redis->select((int) $params['database']);
            }
    
            // Configure options safely
            try {
                if (defined('Redis::OPT_SERIALIZER')) {
                    $this->redis->setOption(\Redis::OPT_SERIALIZER, \Redis::SERIALIZER_PHP);
                }
                if (defined('Redis::OPT_PREFIX')) {
                    $this->redis->setOption(\Redis::OPT_PREFIX, '');
                }
            } catch (\Exception $e) {
                error_log('Redis Cache: Could not set Redis options - ' . $e->getMessage());
            }
    
            $this->diagnostics += $params;
    
        } catch (\Exception $e) {
            throw new \RedisException('Redis connection failed: ' . $e->getMessage(), 0, $e);
        }
    }

    /**
    * Connect using Relay extension.
    */
    private function connect_relay(array $params): void {
        $ver = \phpversion('relay');
        $this->diagnostics['client'] = "Relay (v{$ver})";
        $this->redis = new \Relay\Relay();
    
        // Determine connection parameters based on scheme
        $host = strcasecmp($params['scheme'], 'unix') === 0 ? $params['path'] : $params['host'];
        $port = strcasecmp($params['scheme'], 'unix') === 0 ? 0 : (int) $params['port'];
    
        if ($params['persistent']) {
            $this->redis->pconnect(
                $host,
                $port,
                (float) $params['timeout'],
                $params['persistent_id'] ?? null,
                (int) $params['retry_interval']
            );
        } else {
            $this->redis->connect(
                $host,
                $port,
                (float) $params['timeout'],
                null,
                (int) $params['retry_interval']
            );
        }
    
        if (!empty($params['password'])) {
            $this->redis->auth($params['password']);
        }
        if (!empty($params['database'])) {
            $this->redis->select((int) $params['database']);
        }
    
        $this->diagnostics += $params;
    }

    /**
     * Connect using Predis library (bundled or auto-loaded).
     */
    private function connect_predis(array $params): void {
        if (!class_exists('\Predis\Client')) {
            throw new \Exception('Predis library not found. Please install Predis or choose a different client.');
        }
        
        $this->diagnostics['client'] = 'Predis';
    
        if (!empty($params['read_timeout'])) {
            $params['read_write_timeout'] = $params['read_timeout'];
        }
    
        $options = [];
        $this->redis = new \Predis\Client($params, $options);
        $this->redis->connect();
        $this->diagnostics += $params;
    }

    /**
     * Fetch Redis info and store version.
     */
    public function fetch_info(): void {
        $info = $this->redis->info();
        if (isset($info['redis_version'])) {
            $this->redis_version = $info['redis_version'];
        } elseif (isset($info['Server']['redis_version'])) {
            $this->redis_version = $info['Server']['redis_version'];
        }
    }

    /**
     * Is Redis connected & available?
     */
    public function redis_status(): bool {
        return $this->redis_connected;
    }

    /**
     * Return the underlying Redis instance.
     */
    public function redis_instance(): mixed {
        return $this->redis;
    }

    /**
     * Return the detected Redis server version.
     */
    public function redis_version(): ?string {
        return $this->redis_version;
    }

    /**
     * Add data if key does not exist.
     */
    public function add(string $key, mixed $value, string $group = 'default', int|null $expiration = null): bool {
        return $this->add_or_replace(true, $key, $value, $group, $expiration);
    }

    /**
     * Adds multiple values at once.
     */
    public function add_multiple(array $data, string $group = 'default', int $expire = 0): array {
        $results = [];
        foreach ($data as $k => $v) {
            $results[$k] = $this->add($k, $v, $group, $expire);
        }
        return $results;
    }

    /**
     * Replace data if the key already exists.
     */
    public function replace(string $key, mixed $value, string $group = 'default', int|null $expiration = null): bool {
        return $this->add_or_replace(false, $key, $value, $group, $expiration);
    }

    /**
     * Common add-or-replace logic.
     */
    private function add_or_replace(bool $isAdd, string $key, mixed $value, string $group, int|null $expiration): bool {
        $derived = $this->build_key($key, $group);
        $inMemoryExists = array_key_exists($derived, $this->cache);
        $this->store_in_runtime_cache($derived, $value); // Fixed - using $derived instead of $dk
        
        if ($isAdd && $inMemoryExists) {
            return false;
        }
        if (!$isAdd && !$inMemoryExists && $this->redis_status()) {
            if (!$this->redis->exists($derived)) {
                return false;
            }
        }
        
        if ($this->is_ignored_group($group) || !$this->redis_status()) {
            $this->store_in_runtime_cache($derived, $value);
            return true;
        }
        
        $expiration = $this->validate_expiration($expiration);
        
        try {
            $serialized = $this->maybe_serialize($value);
            if ($isAdd) {
                $result = $expiration
                    ? $this->parse_redis_response($this->redis->set($derived, $serialized, ['nx', 'ex' => $expiration]))
                    : $this->parse_redis_response($this->redis->setnx($derived, $serialized));
            } else {
                $result = $expiration
                    ? $this->parse_redis_response($this->redis->setex($derived, $expiration, $serialized))
                    : $this->parse_redis_response($this->redis->set($derived, $serialized));
            }
        
            if ($result) {
                $this->store_in_runtime_cache($derived, $value);
            }
            return (bool)$result;
        } catch (\Exception $e) {
            $this->handle_exception($e);
            return false;
        }
    }

    /**
     * Configure runtime cache settings
     * 
     * @param int $max_entries Maximum number of entries to keep in runtime cache
     * @return void
     */
    public function configure_runtime_cache(int $max_entries = 1000): void {
        $this->max_runtime_entries = max(1, $max_entries);
        
        // If we're already over the new limit, trim the cache
        while ($this->cacheEvictionQueue->count() > $this->max_runtime_entries) {
            $oldestKey = $this->cacheEvictionQueue->dequeue();
            unset($this->cache[$oldestKey]);
        }
    }

    /**
     * Delete an item from the cache.
     */
    public function delete(string $key, string $group = 'default', int $deprecated = 0): bool {
        $derived = $this->build_key($key, $group);
        unset($this->cache[$derived]); // remove from runtime

        if (!$this->redis_status() || $this->is_ignored_group($group)) {
            return true;
        }

        $startTime = microtime(true);
        try {
            $result = $this->parse_redis_response($this->redis->del($derived));
        } catch (\Exception $e) {
            $this->handle_exception($e);
            return false;
        }
        $this->cache_calls++;
        $this->cache_time += (microtime(true) - $startTime);

        return (bool)$result;
    }

    /**
     * Delete multiple items at once.
     */
    public function delete_multiple(array $keys, string $group = 'default'): array {
        $results = [];
        foreach ($keys as $k) {
            $results[$k] = $this->delete($k, $group);
        }
        return $results;
    }

    /**
     * Flush entire cache. If WP_REDIS_SELECTIVE_FLUSH, flush only matching prefix.
     */
    public function flush(): bool {
        $this->cache = [];
        if (!$this->redis_status()) {
            return false;
        }

        $start   = microtime(true);
        $prefix  = defined('WP_REDIS_PREFIX') ? trim(WP_REDIS_PREFIX) : '';
        $selective = defined('WP_REDIS_SELECTIVE_FLUSH') && WP_REDIS_SELECTIVE_FLUSH;

        try {
            if ($selective && $prefix !== '') {
                $res = $this->execute_lua_flush($prefix);
            } else {
                $res = $this->parse_redis_response($this->redis->flushDB());
            }
        } catch (\Exception $e) {
            $this->handle_exception($e);
            return false;
        }
        $this->cache_calls++;
        $this->cache_time += (microtime(true) - $start);

        return (bool)$res;
    }

    /**
    * Remove all items from a specific group using SCAN for safety.
    * 
    * @param string $group Cache group to flush
    * @return bool True if any keys were removed, false otherwise
    */
    public function flush_group(string $group): bool {
        if (in_array($group, $this->unflushable_groups, true)) {
            return false;
        }
    
        // Initialize stats for this operation
        $this->flush_stats = [
            'started' => microtime(true),
            'keys_scanned' => 0,
            'keys_deleted' => 0,
            'batches' => 0
        ];
    
        // Clear matching keys from runtime cache first
        $group = $this->sanitize_key_part($group);
        $runtime_cleared = 0;
        foreach ($this->cache as $k => $_) {
            if (str_contains($k, ":{$group}:")) {
                unset($this->cache[$k]);
                $runtime_cleared++;
            }
        }
    
        if (!$this->redis_status()) {
            return $runtime_cleared > 0;
        }
    
        $pattern = $this->build_key('*', $group);
        $success = false;
        
        // Try different strategies based on Redis version
        try {
            if (version_compare($this->redis_version, '6.0.0', '>=')) {
                $success = $this->flush_group_unlink($pattern);
            } else {
                $success = $this->flush_group_scan($pattern);
            }
        } catch (\Exception $e) {
            $this->handle_exception($e);
            return false;
        }
    
        // Log operation statistics
        $this->log_flush_stats($group);
        
        return $success;
    }
    
    /**
     * Add these new methods to support the improved flush_group
     */
    private function flush_group_unlink(string $pattern): bool {
        $cursor = '0';
        $deleted = 0;
        
        do {
            try {
                $keys = $this->redis->scan(
                    $cursor,
                    ['match' => $pattern, 'count' => self::SCAN_COUNT]
                );
                
                $this->flush_stats['keys_scanned'] += count($keys);
                
                if (!empty($keys)) {
                    $result = $this->redis->unlink($keys);
                    if ($result) {
                        $deleted += $result;
                        $this->flush_stats['keys_deleted'] += $result;
                    }
                }
                
                $this->flush_stats['batches']++;
                
            } catch (\Exception $e) {
                error_log('Redis Cache: Error during unlink flush - ' . $e->getMessage());
                return false;
            }
        } while ($cursor !== '0');
        
        return $deleted > 0;
    }

    private function flush_group_scan(string $pattern): bool {
        $cursor = '0';
        $deleted = 0;
        $pipe = null;
        $pipeline_count = 0;
        
        do {
            try {
                $keys = $this->redis->scan(
                    $cursor,
                    ['match' => $pattern, 'count' => self::SCAN_COUNT]
                );
                
                $this->flush_stats['keys_scanned'] += count($keys);
                
                if (!empty($keys)) {
                    if (!$pipe) {
                        $pipe = $this->redis->multi(\Redis::PIPELINE);
                    }
                    
                    foreach ($keys as $key) {
                        $pipe->del($key);
                        $pipeline_count++;
                        
                        if ($pipeline_count >= self::MAX_PIPELINE_SIZE) {
                            $results = $pipe->exec();
                            $deleted += array_sum($results);
                            $this->flush_stats['keys_deleted'] += array_sum($results);
                            $pipe = $this->redis->multi(\Redis::PIPELINE);
                            $pipeline_count = 0;
                        }
                    }
                }
                
                $this->flush_stats['batches']++;
                
            } catch (\Exception $e) {
                if ($pipe) {
                    try {
                        $pipe->discard();
                    } catch (\Exception $e) {
                        // Ignore discard errors
                    }
                }
                error_log('Redis Cache: Error during scan flush - ' . $e->getMessage());
                return false;
            }
        } while ($cursor !== '0');
        
        // Execute any remaining pipeline operations
        if ($pipe && $pipeline_count > 0) {
            try {
                $results = $pipe->exec();
                $deleted += array_sum($results);
                $this->flush_stats['keys_deleted'] += array_sum($results);
            } catch (\Exception $e) {
                error_log('Redis Cache: Error executing final pipeline - ' . $e->getMessage());
            }
        }
        
        return $deleted > 0;
    }
    
    private function log_flush_stats(string $group): void {
        $duration = microtime(true) - $this->flush_stats['started'];
        if ($this->flush_stats['keys_deleted'] > 1000 || $duration > 1.0) {
            error_log(sprintf(
                'Redis Cache: Flushed group "%s" - Scanned: %d, Deleted: %d, Batches: %d, Time: %.2fs',
                $group,
                $this->flush_stats['keys_scanned'],
                $this->flush_stats['keys_deleted'],
                $this->flush_stats['batches'],
                $duration
            ));
        }
    }

    /**
     * Flush runtime-only cache.
     */
    public function flush_runtime(): bool {
        $this->cache = [];
        return true;
    }

    /**
     * Get a value from cache.
     */
    public function get(string $key, string $group = 'default', bool $force = false, ?bool &$found = null): mixed {
        $derived = $this->build_key($key, $group);
    
        if (!$force && array_key_exists($derived, $this->cache)) {
            $found = true;
            $this->cache_hits++;
            return $this->cache[$derived];
        }
    
        if ($this->is_ignored_group($group) || !$this->redis_status()) {
            $found = false;
            $this->cache_misses++;
            return false;
        }
    
        $startTime = microtime(true);
        try {
            $value = $this->redis->get($derived);
        } catch (\Exception $e) {
            $this->handle_exception($e);
            $found = false;
            return false;
        }
        $this->cache_calls++;
        $this->cache_time += (microtime(true) - $startTime);
    
        if ($value === null || $value === false) {
            $found = false;
            $this->cache_misses++;
            return false;
        }
    
        $found = true;
        $this->cache_hits++;
        $value = $this->maybe_unserialize($value);
        $this->store_in_runtime_cache($derived, $value);
    
        return $value;
    }

    /**
     * Get multiple values at once.
     */
    public function get_multiple(array $keys, string $group = 'default', bool $force = false): array {
        if (!is_array($keys)) {
            return [];
        }
    
        $derived_keys = array_map(fn($key) => $this->build_key($key, $group), $keys);
        $key_map = array_combine($derived_keys, $keys);
        
        // Get from runtime cache first if not forcing
        $results = [];
        $missing_keys = [];
        
        if (!$force) {
            foreach ($derived_keys as $dk) {
                if (array_key_exists($dk, $this->cache)) {
                    $results[$key_map[$dk]] = $this->cache[$dk];
                } else {
                    $missing_keys[] = $dk;
                }
            }
        } else {
            $missing_keys = $derived_keys;
        }
    
        if (empty($missing_keys) || $this->is_ignored_group($group) || !$this->redis_status()) {
            return $results + array_fill_keys(array_diff($keys, array_keys($results)), false);
        }
    
        try {
            $values = $this->redis->mget($missing_keys);
            foreach ($missing_keys as $i => $dk) {
                $value = $values[$i] ?? false;
                if ($value !== false && $value !== null) {
                    $value = $this->maybe_unserialize($value);
                    $this->store_in_runtime_cache($dk, $value);
                    $results[$key_map[$dk]] = $value;
                    $this->cache_hits++;
                } else {
                    $results[$key_map[$dk]] = false;
                    $this->cache_misses++;
                }
            }
        } catch (\Exception $e) {
            $this->handle_exception($e);
            foreach ($missing_keys as $dk) {
                $results[$key_map[$dk]] = false;
                $this->cache_misses++;
            }
        }
    
        return $results;
    }

    /**
     * Set a value in cache (unconditionally).
     * @param int|null $expiration Number of seconds to cache. 0 or null = permanent.
     */
    public function set(
        string $key, 
        mixed $value, 
        string $group = 'default', 
        int|null $expiration = null
    ): bool {
        $derived = $this->build_key($key, $group);

        if ($this->is_ignored_group($group) || !$this->redis_status()) {
            $this->store_in_runtime_cache($derived, $value);
            return true;
        }

        $expiration = $this->validate_expiration($expiration);
        $startTime = microtime(true);
        try {
            $serialized = $this->maybe_serialize($value);
            $result = $expiration
                ? $this->parse_redis_response($this->redis->setex($derived, $expiration, $serialized))
                : $this->parse_redis_response($this->redis->set($derived, $serialized));
        } catch (\Exception $e) {
            $this->handle_exception($e);
            return false;
        }
        $this->cache_calls++;
        $this->cache_time += (microtime(true) - $startTime);

        if ($result) {
            $this->store_in_runtime_cache($derived, $value);
        }
        return (bool)$result;
    }

    /**
    * Set multiple values at once.
    */
    public function set_multiple(array $data, string $group = 'default', int $expiration = 0): array {
        if ($this->redis_status() && method_exists($this->redis, 'pipeline')) {
            return $this->set_multiple_pipelined($data, $group, $expiration);
        }
        
        $results = [];
        foreach ($data as $k => $v) {
            $results[$k] = $this->set($k, $v, $group, $expiration);
        }
        return $results;
    }

    /**
     * Set a value with automatic TTL for query caches
     */
    private function set_query_cache(string $key, mixed $value, string $group = 'default'): bool {
        // If key contains timestamp, set TTL
        if (preg_match('/\d{10}(\.\d+)?$/', $key)) {
            // Set TTL to 1 hour for query caches
            return $this->set($key, $value, $group, 3600);
        }
        return $this->set($key, $value, $group);
    }

    /**
     * Clean expired query caches
     */
    public function clean_expired_query_caches(): bool {
        if (!$this->redis_status()) {
            return false;
        }

        $script = <<<LUA
        local keys = redis.call('KEYS', ARGV[1])
        local count = 0
        local now = tonumber(ARGV[2])
        for _, key in ipairs(keys) do
            local timestamp = tonumber(string.match(key, '(%d+)%.?%d*$'))
            if timestamp and timestamp < now - 3600 then
                redis.call('DEL', key)
                count = count + 1
            end
        end
        return count
    LUA;

        try {
            $pattern = $this->build_key('*-queries:*', '*');
            $now = time();
            $result = $this->redis->eval($script, [$pattern, $now], 1);
            return $result > 0;
        } catch (\Exception $e) {
            $this->handle_exception($e);
            return false;
        }
    }

    /**
    * Set multiple values using Redis pipeline for better performance.
    * 
    * @param array  $data     Array of key => value pairs to set
    * @param string $group    Cache group
    * @param int    $expiration Expiration time in seconds
    * @return array Array of keys mapped to success/failure status
    */
    private function set_multiple_pipelined(array $data, string $group, int $expiration): array {
        if (!$this->redis_status() || !method_exists($this->redis, 'pipeline')) {
            // Fallback to individual sets if pipeline not available
            $results = [];
            foreach ($data as $key => $value) {
                $results[$key] = $this->set($key, $value, $group, $expiration);
            }
            return $results;
        }

        // Split into manageable batches to prevent memory issues
        $batchSize = 1000; // Adjust based on your needs
        $results = [];
        $batches = array_chunk($data, $batchSize, true);

        foreach ($batches as $batch) {
            try {
                // Start pipeline in MULTI mode for atomicity
                $pipe = $this->redis->multi(\Redis::PIPELINE);
                $derived_keys = [];

                foreach ($batch as $key => $value) {
                    $derived = $this->build_key($key, $group);
                    $derived_keys[$derived] = $key;
                    
                    $serialized = $this->maybe_serialize($value);
                    
                    if ($expiration) {
                        $pipe->setex($derived, $expiration, $serialized);
                    } else {
                        $pipe->set($derived, $serialized);
                    }
                    
                    // Update runtime cache immediately
                    $this->store_in_runtime_cache($derived, $value);
                }

                // Execute pipeline
                $responses = $pipe->exec();
                
                // Map responses back to original keys
                if (is_array($responses)) {
                    $i = 0;
                    foreach ($derived_keys as $derived => $original_key) {
                        $results[$original_key] = isset($responses[$i]) && 
                            $this->parse_redis_response($responses[$i]);
                        $i++;
                    }
                } else {
                    // Handle pipeline execution failure
                    foreach ($derived_keys as $derived => $original_key) {
                        $results[$original_key] = false;
                    }
                }

            } catch (\Exception $e) {
                // Log error but continue with other batches
                $this->handle_exception($e);
                
                // Mark all keys in failed batch as false
                foreach ($batch as $key => $_) {
                    $results[$key] = false;
                }
                
                // Try to abort pipeline if possible
                try {
                    $pipe->discard();
                } catch (\Exception $e) {
                    // Ignore discard errors
                }
            }
        }

        return $results;
    }

    /**
     * Increment a numeric value by $offset.
     */
    public function increment(string $key, int $offset = 1, string $group = 'default'): int|bool {
        $derived = $this->build_key($key, $group);
        if ($this->is_ignored_group($group) || !$this->redis_status()) {
            $old = (int)($this->cache[$derived] ?? 0);
            $new = $old + $offset;
            $this->cache[$derived] = $new;
            return $new;
        }
        $start = microtime(true);
        try {
            $result = $this->redis->incrBy($derived, $offset);
            $this->cache[$derived] = (int)$this->redis->get($derived);
        } catch (\Exception $e) {
            $this->handle_exception($e);
            return false;
        }
        $this->cache_calls += 2;
        $this->cache_time  += (microtime(true) - $start);
        return $result;
    }

    /**
     * Decrement a numeric value by $offset.
     */
    public function decrement(string $key, int $offset = 1, string $group = 'default'): int|bool {
        $derived = $this->build_key($key, $group);
        if ($this->is_ignored_group($group) || !$this->redis_status()) {
            $old = (int)($this->cache[$derived] ?? 0);
            $new = max(0, $old - $offset);
            $this->cache[$derived] = $new;
            return $new;
        }

        $start = microtime(true);
        try {
            $result = $this->redis->decrBy($derived, $offset);
            $this->cache[$derived] = (int)$this->redis->get($derived);
        } catch (\Exception $e) {
            $this->handle_exception($e);
            return false;
        }
        $this->cache_calls += 2;
        $this->cache_time  += (microtime(true) - $start);
        return $result;
    }

    /**
     * Display some basic stats (used by Debug Bar or similar).
     */
    public function stats(): void {
        echo '<p><strong>Redis Status:</strong> ' . ($this->redis_status() ? 'Connected' : 'Not Connected') . '<br />';
        echo '<strong>Client:</strong> ' . ($this->diagnostics['client'] ?? 'Unknown') . '<br />';
        echo '<strong>Hits:</strong> ' . $this->cache_hits . '<br />';
        echo '<strong>Misses:</strong> ' . $this->cache_misses . '<br />';
        echo '<strong>Cache Size (Runtime):</strong> ' . number_format_i18n(strlen(serialize($this->cache)) / 1024, 2) . ' KB</p>';
    }

    /**
     * Returns an object with stats and metadata.
     */
    public function info(): object {
        $total = $this->cache_hits + $this->cache_misses;
        return (object)[
            'hits'   => $this->cache_hits,
            'misses' => $this->cache_misses,
            'ratio'  => $total > 0 ? round($this->cache_hits / ($total / 100), 1) : 100,
            'time'   => $this->cache_time,
            'calls'  => $this->cache_calls,
            'errors' => !empty($this->errors) ? $this->errors : null,
            'meta'   => [
                'Client'        => $this->diagnostics['client'] ?? 'Unknown',
                'Redis Version' => $this->redis_version,
            ],
        ];
    }

    /**
     * Switch blog ID (multisite).
     */
    public function switch_to_blog(int $_blog_id): bool {
        if (!function_exists('is_multisite') || !is_multisite()) {
            return false;
        }
        $this->blog_prefix = $_blog_id;
        return true;
    }

    /**
     * Batch get multiple transients at once
     */
    private function get_site_transients(array $keys): array {
        $derived_keys = array_map(function($key) {
            return $this->build_key($key, 'site-transient');
        }, $keys);
        
        if (!$this->redis_status()) {
            return array_fill_keys($keys, false);
        }
    
        try {
            $values = $this->redis->mget($derived_keys);
            $result = [];
            foreach ($keys as $i => $key) {
                $value = $values[$i] ?? false;
                if ($value !== false && $value !== null) {
                    $unserialized = $this->maybe_unserialize($value);
                    $result[$key] = $unserialized;
                    $this->store_in_runtime_cache($derived_keys[$i], $unserialized); // Fixed: storing unserialized value
                } else {
                    $result[$key] = false;
                }
            }
            return $result;
        } catch (\Exception $e) {
            $this->handle_exception($e);
            return array_fill_keys($keys, false);
        }
    }

    /**
     * Get all update status checks at once
     */
    public function get_update_status(): array {
        $keys = ['update_plugins', 'update_themes', 'update_core'];
        return $this->get_site_transients($keys);
    }

    /**
     * Mark certain groups as global. If Redis is offline, they become ignored.
     */
    public function add_global_groups(array|string $groups): void {
        $arr = (array)$groups;
        if ($this->redis_status()) {
            $this->global_groups = array_unique(array_merge($this->global_groups, $arr));
        } else {
            $this->ignored_groups = array_unique(array_merge($this->ignored_groups, $arr));
        }
        $this->cache_group_types();
    }

    /**
     * Mark certain groups as non-persistent (ignored).
     */
    public function add_non_persistent_groups(array|string $groups): void {
        $arr = (array)$groups;
        $this->ignored_groups = array_unique(array_merge($this->ignored_groups, $arr));
        $this->cache_group_types();
    }

    /**
     * Execute a LUA script to selectively remove keys matching a pattern.
     */
    private function execute_lua_flush(string $pattern): bool|int {
        // Basic SCAN + DEL script
        $script = <<<LUA
local cur=0
local count=0
repeat
    local scan=redis.call("SCAN", cur, "MATCH", KEYS[1], "COUNT", 1000)
    cur=tonumber(scan[1])
    for _,key in ipairs(scan[2]) do
        redis.call("DEL", key)
        count=count+1
    end
until cur==0
return count
LUA;

        try {
            $resp = $this->redis->eval($script, [$pattern . '*'], 1);
            return $this->parse_redis_response($resp);
        } catch (\Exception $e) {
            $this->handle_exception($e);
            return false;
        }
    }

    private ?int $current_database = null;

    /**
     * Ensure we're using the correct database
     */
    private function ensure_database(int $db): bool {
        if (!$this->redis_status()) {
            return false;
        }
    
        // If we're already on the right DB, no need to switch
        if ($this->current_database === $db) {
            return true;
        }
    
        // Check if this DB has had recent failures
        if (isset($this->db_switch_failures[$db])) {
            $failure = $this->db_switch_failures[$db];
            if (time() - $failure['time'] < 300) { // 5-minute cooldown
                if ($failure['count'] >= self::MAX_DB_SWITCH_RETRIES) {
                    // Use fallback database if too many recent failures
                    return $this->use_fallback_database($db);
                }
            } else {
                // Reset failure count after cooldown
                unset($this->db_switch_failures[$db]);
            }
        }
    
        try {
            // Verify DB exists before switching
            $dbs = $this->get_database_count();
            if ($db >= $dbs) {
                throw new \RedisException("Database $db does not exist (max: " . ($dbs-1) . ")");
            }
    
            // Attempt database switch
            $result = $this->redis->select($db);
            if (!$result) {
                throw new \RedisException("Failed to switch to database $db");
            }
    
            // Success - update current database
            $this->current_database = $db;
            return true;
    
        } catch (\Exception $e) {
            // Track failure
            $this->track_db_switch_failure($db);
            
            // Log the error
            error_log(sprintf(
                'Redis Cache: Database switch error - DB: %d, Error: %s',
                $db,
                $e->getMessage()
            ));
    
            // Try fallback database
            return $this->use_fallback_database($db);
        }
    }

     /**
     * Build key with database selection
     */

    private function get_database_count(): int {
        try {
            $info = $this->redis->info('keyspace');
            return count($info ?? []);
        } catch (\Exception $e) {
            // Fallback to default max databases (typically 16)
            return 16;
        }
    }

    private function track_db_switch_failure(int $db): void {
        if (!isset($this->db_switch_failures[$db])) {
            $this->db_switch_failures[$db] = [
                'count' => 0,
                'time' => time()
            ];
        }
        
        $this->db_switch_failures[$db]['count']++;
        $this->db_switch_failures[$db]['time'] = time();
    }

    private function use_fallback_database(int $attempted_db): bool {
        // If no fallback set, try to use DB 0
        if ($this->fallback_database === null) {
            try {
                if ($this->redis->select(0)) {
                    $this->fallback_database = 0;
                    $this->current_database = 0;
                }
            } catch (\Exception $e) {
                error_log('Redis Cache: Failed to set fallback database: ' . $e->getMessage());
                return false;
            }
        }

        // Log fallback usage
        if ($this->fallback_database !== null) {
            error_log(sprintf(
                'Redis Cache: Using fallback database %d instead of %d',
                $this->fallback_database,
                $attempted_db
            ));
            return true;
        }

        return false;
    }

    // Add method to reset failure tracking
    public function reset_db_switch_failures(): void {
        $this->db_switch_failures = [];
    }

    // Modify build_key method to handle database switching failures
    public function build_key(string $key, string $group = 'default'): string {
        $group = $group ?: 'default';
        $g = $this->sanitize_key_part($group);

        // Determine target database
        $target_db = $this->is_global_group($g) ? 0 : 1;
        
        // Try to switch database, fall back to current if failed
        if (!$this->ensure_database($target_db)) {
            error_log(sprintf(
                'Redis Cache: Failed to switch to DB %d for group %s, using current DB %d',
                $target_db,
                $group,
                $this->current_database ?? 0
            ));
        }

        if (!isset($this->prefix_cache[$g])) {
            $salt = defined('WP_REDIS_PREFIX') ? trim(WP_REDIS_PREFIX) : '';
            $prefix = $this->is_global_group($g) ? (string)$this->global_prefix : (string)$this->blog_prefix;
            $prefix = trim($prefix, '_-:$');
            $this->prefix_cache[$g] = "{$salt}{$prefix}:{$g}:";
        }

        return $this->prefix_cache[$g] . $this->sanitize_key_part($key);
    }

    /**
     * Ensure colons don't break the key naming scheme.
     */
    private function sanitize_key_part(string $part): string {
        return str_replace(':', '-', $part);
    }

    /**
     * Check if group is "ignored" from Redis.
     */
    private function is_ignored_group(string $group): bool {
        return ($this->group_type[$group] ?? null) === 'ignored';
    }

    /**
     * Check if group is "global."
     */
    private function is_global_group(string $group): bool {
        return ($this->group_type[$group] ?? null) === 'global';
    }

    /**
     * Validate and normalize the expiration value.
     * 
     * @param int|null $expiration The expiration time in seconds
     * @return int Normalized expiration time (0 for permanent or invalid values)
     */

    private function validate_expiration(int|null $expiration = null): int {
        // Convert null to 0 (permanent)
        if ($expiration === null) {
            return 0;
        }

        // Ensure integer type and handle negative values
        $expiration = (int) $expiration;
        if ($expiration < 0) {
            return 0;
        }

        // Apply maximum TTL if configured
        if (defined('WP_REDIS_MAXTTL')) {
            $max = (int) WP_REDIS_MAXTTL;
            if ($expiration === 0 || $expiration > $max) {
                return $max;
            }
        }

        return $expiration;
    }

    /**
     * Convert Redis response into something meaningful.
     */
    private function parse_redis_response(mixed $resp): mixed {
        if (is_bool($resp) || is_numeric($resp)) {
            return $resp;
        }
        if (is_object($resp) && method_exists($resp, 'getPayload')) {
            return $resp->getPayload() === 'OK';
        }
        // Some commands return 'OK', others return int, or nil
        return $resp === 'OK';
    }

    /**
     * Handle Redis failure gracefully or throw an exception.
     */
    private function handle_exception(\Exception $e): void {
        $context = [
            'error' => $e->getMessage(),
            'code' => $e->getCode(),
            'file' => $e->getFile(),
            'line' => $e->getLine()
        ];
    
        if ($e instanceof \RedisException) {
            switch ($e->getCode()) {
                case \Redis::ERR_READONLY:
                    $context['type'] = 'readonly_error';
                    break;
                case \Redis::ERR_CONNECTED:
                    $context['type'] = 'connection_error';
                    // Attempt reconnection for connection errors
                    if ($this->attempt_reconnect()) {
                        error_log('Redis: Successfully reconnected after connection error');
                        return; // Exit if reconnection successful
                    }
                    break;
                default:
                    $context['type'] = 'redis_error';
            }
        }
    
        // Only mark as disconnected if reconnection failed or wasn't attempted
        $this->redis_connected = false;
    
        // Mark global groups as ignored only if we're truly disconnected
        $this->ignored_groups = array_unique(array_merge($this->ignored_groups, $this->global_groups));
    
        error_log(sprintf(
            'Redis Error: %s (Type: %s, Code: %d)',
            $e->getMessage(),
            $context['type'] ?? 'unknown',
            $e->getCode()
        ));
    
        if (function_exists('do_action')) {
            do_action('redis_object_cache_error', $e, $e->getMessage());
        }
    
        $this->errors[] = $e->getMessage();
        if (!$this->fail_gracefully) {
            $this->show_error_and_die($e);
        }
    }

    /**
     * Show an admin-like error screen or custom WP_CONTENT_DIR/redis-error.php
     */
    private function show_error_and_die(\Exception $ex): void {
        if (file_exists(WP_CONTENT_DIR . '/redis-error.php')) {
            require WP_CONTENT_DIR . '/redis-error.php';
            die;
        }

        $message  = '<h1>Redis Connection Error</h1>';
        $message .= '<p><code>' . $ex->getMessage() . '</code></p>';
        $message .= '<p>If this is unexpected, check your Redis config or constants in wp-config.php.</p>';

        wp_die($message);
    }

}

endif; // END if (!WP_REDIS_DISABLED)