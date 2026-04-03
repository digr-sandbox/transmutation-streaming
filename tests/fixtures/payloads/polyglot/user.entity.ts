/**
 * This file is a compatibility layer for existing code that imports User from the user module.
 * It re-exports the User entity from the users module.
 *
 * @deprecated Import User from the users module instead
 */

export { User } from '../../users/entities/user.entity';
