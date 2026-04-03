import {
  ExceptionFilter,
  Catch,
  ArgumentsHost,
  HttpStatus,
  HttpException,
} from '@nestjs/common';
import { FastifyRequest, FastifyReply } from 'fastify';
import { LoggerService } from '../../../logger/logger.service';

@Catch()
export class AllExceptionsFilter implements ExceptionFilter {
  constructor(private readonly logger: LoggerService) {}

  catch(exception: unknown, host: ArgumentsHost) {
    const ctx = host.switchToHttp();
    const response = ctx.getResponse<FastifyReply>();
    const request = ctx.getRequest<FastifyRequest>();

    let status = HttpStatus.INTERNAL_SERVER_ERROR;
    let message = 'Internal Server Error';

    // If the exception is an HttpException, use its status code and message
    if (exception instanceof HttpException) {
      status = exception.getStatus();
      const exceptionResponse = exception.getResponse();
      message =
        typeof exceptionResponse === 'object' && exceptionResponse['message']
          ? exceptionResponse['message']
          : exception.message;
    }

    // For security, don't expose error details in production
    const errorResponse = {
      statusCode: status,
      message:
        process.env.NODE_ENV === 'production' ? message : String(exception),
      timestamp: new Date().toISOString(),
      path: request.url,
    };

    // Always log the full exception in the server logs
    this.logger.error(
      `Unhandled exception: ${request.method} ${request.url}`,
      exception instanceof Error ? exception.stack : String(exception),
      'AllExceptionsFilter',
    );

    response.status(status).send(errorResponse);
  }
}
