module.exports = {
  apps: [
    {
      name: 'perennia-web',
      script: 'start-https.py',
      interpreter: 'python3',
      instances: 1,
      exec_mode: 'fork',
      cwd: '/home/perennia/htdocs/www.perennia.org',
      env: {
        PORT: 443,
        HOST: '0.0.0.0',
      },
      error_file: './logs/err.log',
      out_file: './logs/out.log',
      log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
      merge_logs: true,
      autorestart: true,
      watch: false,
      ignore_watch: ['node_modules', 'certs', 'data'],
      max_memory_restart: '1G',
    }
  ]
};
