import {
  Controller,
  Post,
  UseGuards,
  Request,
  Body,
  Get,
  HttpCode,
  BadRequestException,
  Headers,
  Req,
  UnauthorizedException,
  InternalServerErrorException,
  Logger,
} from '@nestjs/common';
import {
  ApiTags,
  ApiOperation,
  ApiResponse,
  ApiBody,
  ApiBearerAuth,
} from '@nestjs/swagger';
import { AuthService } from './auth.service';
import { LocalAuthGuard } from './guards/local-auth.guard';
import { JwtAuthGuard } from './guards/jwt-auth.guard';
import {
  LoginDto,
  RegisterDto,
  RefreshTokenDto,
  ForgotPasswordDto,
  ResetPasswordDto,
} from './dto';
import { CurrentUser } from './current-user.decorator';
import { FastifyRequest } from 'fastify';
import { PermissionsService } from '../permissions/services/permissions.service';
import { UsersService } from '../users/users.service';

@ApiTags('auth')
@Controller('auth')
export class AuthController {
  private readonly logger = new Logger(AuthController.name);

  constructor(
    private readonly authService: AuthService,
    private readonly permissionsService: PermissionsService,
    private readonly usersService: UsersService,
  ) {}

  @ApiOperation({ summary: 'Login user and get token' })
  @ApiBody({ type: LoginDto })
  @ApiResponse({ status: 200, description: 'Login successful' })
  @ApiResponse({ status: 401, description: 'Unauthorized' })
  @UseGuards(LocalAuthGuard)
  @Post('login')
  @HttpCode(200)
  async login(@Body() loginDto: LoginDto, @Req() request: FastifyRequest) {
    try {
      this.logger.log(`Login attempt for user: ${loginDto.email}`);
      const ipAddress = request.ip;
      const userAgent = request.headers['user-agent'] as string;

      const result = await this.authService.login(
        loginDto.email,
        loginDto.password,
        ipAddress,
        userAgent,
        loginDto.captchaToken,
        loginDto.captchaSolution,
      );

      this.logger.log(`Login successful for user: ${loginDto.email}`);
      return result;
    } catch (error) {
      this.logger.error(
        `Login error for user ${loginDto.email}: ${error.message}`,
      );
      if (error.status === 401 || error instanceof UnauthorizedException) {
        throw new UnauthorizedException('Invalid credentials');
      }
      throw new InternalServerErrorException('An error occurred during login');
    }
  }

  @ApiOperation({ summary: 'Register a new user' })
  @ApiBody({ type: RegisterDto })
  @ApiResponse({ status: 201, description: 'User registered successfully' })
  @ApiResponse({ status: 400, description: 'Bad request' })
  @Post('register')
  async register(@Body() registerDto: RegisterDto) {
    return this.authService.register(registerDto);
  }

  @ApiOperation({ summary: 'Refresh access token' })
  @ApiBody({ type: RefreshTokenDto })
  @ApiResponse({ status: 200, description: 'Token refreshed successfully' })
  @ApiResponse({ status: 401, description: 'Unauthorized' })
  @Post('refresh')
  @HttpCode(200)
  async refresh(@Body() refreshTokenDto: RefreshTokenDto) {
    return this.authService.refreshToken(refreshTokenDto.token);
  }

  @ApiOperation({ summary: 'Logout user (invalidate refresh token)' })
  @ApiBody({ type: RefreshTokenDto })
  @ApiResponse({ status: 200, description: 'Logout successful' })
  @Post('logout')
  @HttpCode(200)
  async logout(@Body() refreshTokenDto: RefreshTokenDto) {
    return this.authService.logout(refreshTokenDto.token);
  }

  @ApiOperation({ summary: 'Request password reset' })
  @ApiBody({ type: ForgotPasswordDto })
  @ApiResponse({ status: 200, description: 'Password reset request processed' })
  @Post('forgot-password')
  @HttpCode(200)
  async forgotPassword(@Body() forgotPasswordDto: ForgotPasswordDto) {
    return this.authService.forgotPassword(forgotPasswordDto);
  }

  @Post('verify-email')
  async verifyEmail(@Body() dto: { token: string; email: string }) {
    return this.authService.verifyEmail(dto.token, dto.email);
  }

  @ApiOperation({ summary: 'Reset password with token' })
  @ApiBody({ type: ResetPasswordDto })
  @ApiResponse({ status: 200, description: 'Password reset successfully' })
  @ApiResponse({ status: 400, description: 'Bad request' })
  @ApiResponse({ status: 401, description: 'Unauthorized (invalid token)' })
  @Post('reset-password')
  @HttpCode(200)
  async resetPassword(@Body() resetPasswordDto: ResetPasswordDto) {
    // Validate passwords match
    if (resetPasswordDto.password !== resetPasswordDto.passwordConfirmation) {
      throw new BadRequestException('Passwords do not match');
    }

    return this.authService.resetPassword(resetPasswordDto);
  }

  @ApiOperation({ summary: 'Get current user profile' })
  @ApiResponse({ status: 200, description: 'User profile' })
  @ApiResponse({ status: 401, description: 'Unauthorized' })
  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard)
  @Get('profile')
  getProfile(@Req() req) {
    return req.user;
  }

  @ApiOperation({ summary: 'Validate CSRF token' })
  @ApiResponse({ status: 200, description: 'CSRF token is valid' })
  @ApiResponse({ status: 403, description: 'Invalid CSRF token' })
  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard)
  @Post('validate-csrf')
  @HttpCode(200)
  async validateCsrf(@Headers('x-csrf-token') csrfToken: string, @Req() req) {
    // Implement CSRF token validation logic here
    // This is a placeholder - in a real application you would validate against stored tokens
    if (!csrfToken) {
      throw new BadRequestException('CSRF token is required');
    }

    return { valid: true };
  }

  @ApiOperation({
    summary: 'Diagnostic endpoint to check database schema health',
  })
  @ApiResponse({ status: 200, description: 'Database check results' })
  @Post('diag/db-check')
  @HttpCode(200)
  async checkDatabaseHealth() {
    this.logger.log('Running database health check');
    const results = {
      status: 'checking',
      checks: {
        userCount: 0,
        adminExists: false,
        roleCount: 0,
        permissionCount: 0,
        userRolesCheck: false,
        permissionRelationsCheck: false,
      },
      errors: [],
      recommendations: [],
    };

    try {
      // Check if admin@example.com exists with direct query
      const adminExists =
        await this.usersService.userExistsCheck('admin@example.com');
      results.checks.adminExists = adminExists;

      if (!adminExists) {
        results.errors.push('Admin user does not exist in the database');
        results.recommendations.push(
          'Create an admin user with email admin@example.com',
        );
      }

      // Check total user count
      const userCount = await this.usersService.count();
      results.checks.userCount = userCount;

      if (userCount === 0) {
        results.errors.push('No users exist in the database');
        results.recommendations.push(
          'Database may need to be initialized with seed data',
        );
      }

      // Check permissions count
      const permissions = await this.permissionsService.getAllPermissions();
      results.checks.permissionCount = permissions.length;

      if (permissions.length === 0) {
        results.errors.push('No permissions exist in the database');
        results.recommendations.push(
          'Run permission synchronization to create default permissions',
        );
      }

      // Check role assignments if admin exists
      if (adminExists) {
        try {
          const adminUser =
            await this.usersService.findByEmail('admin@example.com');
          results.checks.userRolesCheck =
            adminUser && adminUser.roles && adminUser.roles.length > 0;

          if (!results.checks.userRolesCheck) {
            results.errors.push('Admin user exists but has no roles assigned');
            results.recommendations.push(
              'Assign the admin role to the admin user',
            );
          }
        } catch (error) {
          results.errors.push(`Error checking admin roles: ${error.message}`);
        }
      }

      // Determine overall status
      if (results.errors.length === 0) {
        results.status = 'healthy';
      } else if (results.errors.length < 3) {
        results.status = 'warning';
      } else {
        results.status = 'critical';
      }

      return results;
    } catch (error) {
      this.logger.error(`Database health check failed: ${error.message}`);
      return {
        status: 'error',
        message: error.message,
        errors: [error.message],
        recommendations: ['Check database connection and schema'],
      };
    }
  }
}
